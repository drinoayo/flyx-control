#!/usr/bin/env python3
"""Reversible Wi-Fi MAC-filter write test for MTN FlyX / ZLT X17U.

This test never uses a real client MAC. It temporarily adds one locally
administered dummy MAC to the router's Wi-Fi deny list, verifies cmd 278
readback, then restores the original state for both 5 GHz and 2.4 GHz.

Real Block/Unblock remains disabled in the Flutter app until this transport and
state lifecycle has been verified on the target firmware.
"""
from __future__ import annotations

import argparse
import copy
import getpass
import json
import sys
from typing import Any

from discover_x17u_auth import login_once, read_command, request_json


DUMMY_MAC = "02:00:00:00:00:01"
BANDS = (("5 GHz", "0"), ("2.4 GHz", "1"))


def write_command(
    host: str,
    cmd: int,
    session_id: str,
    fields: dict[str, Any],
) -> dict[str, Any]:
    token_reply = read_command(host, 233, session_id)
    token = str(token_reply.get("token", ""))
    if not token:
        raise RuntimeError(f"cmd {cmd}: router did not return a write token")

    payload: dict[str, Any] = dict(fields)
    payload.update(
        {
            "cmd": cmd,
            "method": "POST",
            "sessionId": session_id,
            "token": token,
        }
    )
    result = request_json(host, payload)
    if result.get("success") is False:
        raise RuntimeError(
            f"cmd {cmd} refused: {result.get('message', 'unknown error')}"
        )
    message = str(result.get("message", "")).strip()
    if message:
        raise RuntimeError(f"cmd {cmd} refused: {message}")
    return result


def read_filter(
    host: str,
    session_id: str,
    subcmd: str,
) -> dict[str, Any] | None:
    result = read_command(
        host,
        278,
        session_id,
        fields={"subcmd": subcmd},
    )
    datas = result.get("datas")
    if datas is None:
        return None
    if not isinstance(datas, dict):
        raise RuntimeError("cmd 278 returned an unexpected datas shape")
    maclist = datas.get("maclist", [])
    mode = datas.get("macfilter", "close")
    if not isinstance(maclist, list) or not isinstance(mode, str):
        raise RuntimeError("cmd 278 returned an invalid MAC-filter structure")
    return copy.deepcopy(datas)


def normalized_state(datas: dict[str, Any] | None) -> dict[str, Any]:
    if datas is None:
        return {"macfilter": "close", "maclist": []}
    result = copy.deepcopy(datas)
    result.setdefault("macfilter", "close")
    result.setdefault("maclist", [])
    return result


def has_mac(rows: list[Any], mac: str) -> bool:
    needle = mac.lower()
    for row in rows:
        if isinstance(row, dict) and str(row.get("mac", "")).lower() == needle:
            return True
    return False


def same_filter_state(a: dict[str, Any] | None, b: dict[str, Any] | None) -> bool:
    return normalized_state(a) == normalized_state(b)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reversible X17U Wi-Fi MAC-filter write/readback test"
    )
    parser.add_argument("--host", default="192.168.0.1")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    host = (
        args.host.replace("http://", "")
        .replace("https://", "")
        .split("#", 1)[0]
        .rstrip("/")
    )

    if not args.apply:
        print(
            "Dry run only. Re-run with --apply to perform the reversible "
            "dummy-MAC filter test."
        )
        return 0

    prompt = (
        "This makes temporary Wi-Fi MAC-filter writes using only the dummy "
        f"MAC {DUMMY_MAC} and restores the original state. Type APPLY to continue: "
    )
    if args.json:
        print(prompt, file=sys.stderr, end="", flush=True)
        confirmation = input()
    else:
        confirmation = input(prompt)
    if confirmation != "APPLY":
        print("Cancelled.", file=sys.stderr if args.json else sys.stdout)
        return 2

    password = getpass.getpass("FlyX admin password (hidden; not saved): ")
    if not password:
        print("No password entered.", file=sys.stderr)
        return 3

    try:
        session_id = login_once(host, args.username, password)
    except Exception as exc:
        print(f"Login failed: {exc}", file=sys.stderr)
        return 4
    finally:
        password = ""

    report: dict[str, Any] = {
        "test": "wifi-mac-filter-reversible-dummy-mac",
        "dummy_mac": "[dummy-local-admin-mac]",
        "bands": {},
        "all_verified": False,
        "all_restored": False,
    }

    all_verified = True
    all_restored = True

    for label, subcmd in BANDS:
        band: dict[str, Any] = {
            "subcmd": subcmd,
            "original_readable": False,
            "original_mode": None,
            "original_count": None,
            "write_verified": False,
            "restored": False,
        }
        report["bands"][label] = band

        original: dict[str, Any] | None = None
        wrote = False

        try:
            original = read_filter(host, session_id, subcmd)
            state = normalized_state(original)
            mode = str(state.get("macfilter", "close"))
            rows = state.get("maclist", [])

            band["original_readable"] = original is not None
            band["original_mode"] = mode
            band["original_count"] = len(rows)

            if mode == "allow":
                raise RuntimeError(
                    "Refusing to test while this band is in whitelist mode."
                )
            if has_mac(rows, DUMMY_MAC):
                raise RuntimeError(
                    "The dummy MAC is already present; choose a clean test state."
                )

            updated = copy.deepcopy(state)
            updated["macfilter"] = "deny"
            updated_rows = list(updated.get("maclist", []))
            updated_rows.append({"mac": DUMMY_MAC})
            updated["maclist"] = updated_rows

            write_command(
                host,
                278,
                session_id,
                {
                    "datas": updated,
                    "subcmd": subcmd,
                    "success": True,
                },
            )
            wrote = True

            readback = read_filter(host, session_id, subcmd)
            check = normalized_state(readback)
            check_rows = check.get("maclist", [])
            band["write_verified"] = (
                check.get("macfilter") == "deny"
                and isinstance(check_rows, list)
                and has_mac(check_rows, DUMMY_MAC)
            )
            if not band["write_verified"]:
                raise RuntimeError(
                    "cmd 278 readback did not confirm the temporary deny rule."
                )

        except Exception as exc:
            band["error"] = str(exc)
            all_verified = False

        finally:
            if wrote:
                try:
                    restore = normalized_state(original)
                    write_command(
                        host,
                        278,
                        session_id,
                        {
                            "datas": restore,
                            "subcmd": subcmd,
                            "success": True,
                        },
                    )
                    restored_readback = read_filter(host, session_id, subcmd)
                    band["restored"] = same_filter_state(
                        restored_readback,
                        original,
                    )
                    if not band["restored"]:
                        all_restored = False
                        band["cleanup_warning"] = (
                            "Readback does not match the original filter state."
                        )
                except Exception as cleanup_exc:
                    all_restored = False
                    band["cleanup_error"] = str(cleanup_exc)
            elif "error" in band:
                all_restored = False

    report["all_verified"] = all_verified
    report["all_restored"] = all_restored

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=True))
    else:
        print(json.dumps(report, indent=2, ensure_ascii=True))

    return 0 if all_verified and all_restored else 5


if __name__ == "__main__":
    raise SystemExit(main())
