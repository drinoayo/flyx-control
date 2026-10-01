#!/usr/bin/env python3
"""Reversible Parent Control write-path test for MTN FlyX / ZLT X17U.

This tool performs real router writes only when --apply is supplied and the
interactive confirmation is accepted. It creates one DISABLED Parent Control
rule for a selected connected device, applies the stock UI filter command,
verifies readback, then restores the exact original rule list.

The admin password, session ID and write tokens are never printed or saved.
"""
from __future__ import annotations

import argparse
import copy
import getpass
import json
import sys
from typing import Any

from discover_x17u_auth import login_once, read_command, request_json


def write_command(
    host: str,
    cmd: int,
    session_id: str,
    fields: dict[str, Any] | None = None,
) -> dict[str, Any]:
    token_reply = read_command(host, 233, session_id)
    token = str(token_reply.get("token", ""))
    if not token:
        raise RuntimeError(f"cmd {cmd}: router did not return a write token")

    payload: dict[str, Any] = dict(fields or {})
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


def get_parent_rules(host: str, session_id: str) -> list[dict[str, Any]]:
    result = read_command(
        host,
        385,
        session_id,
        fields={"getfun": True},
    )
    rows = result.get("datas")
    if not isinstance(rows, list):
        raise RuntimeError(
            "cmd 385 did not return a readable datas array. "
            "Stop rather than guessing Parent Control state."
        )
    normalized: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise RuntimeError("cmd 385 returned a non-object rule")
        normalized.append(dict(row))
    return normalized


def find_device(
    host: str,
    session_id: str,
    hostname: str,
) -> dict[str, Any]:
    result = read_command(host, 223, session_id)
    rows = result.get("dhcp_list_info")
    if not isinstance(rows, list):
        raise RuntimeError("cmd 223 did not return the connected-device list")

    matches = [
        dict(row)
        for row in rows
        if isinstance(row, dict)
        and str(row.get("hostname", "")).strip().lower() == hostname.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one connected device named {hostname!r}; "
            f"found {len(matches)}."
        )

    ip = str(matches[0].get("ip", "")).strip()
    if not ip:
        raise RuntimeError("The selected device has no LAN IP address.")
    return matches[0]


def same_rules(a: list[dict[str, Any]], b: list[dict[str, Any]]) -> bool:
    return a == b


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reversible disabled Parent Control write test"
    )
    parser.add_argument("--host", default="192.168.0.1")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--hostname", required=True)
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
            "disabled-rule test."
        )
        return 0

    warning = (
        "This will make two real Parent Control writes, but the temporary rule "
        "is DISABLED and the script will restore the original rule list. "
        "Type APPLY to continue: "
    )
    if args.json:
        print(warning, file=sys.stderr, end="", flush=True)
        confirmation = input()
    else:
        confirmation = input(warning)
    if confirmation != "APPLY":
        print("Cancelled.", file=sys.stderr if args.json else sys.stdout)
        return 2

    password = getpass.getpass(
        "FlyX admin password (hidden; not saved): "
    )
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
        "test": "parent-control-reversible-disabled-rule",
        "writes_performed": False,
        "temporary_rule_enabled": False,
        "original_rule_count": None,
        "create_saved": False,
        "apply_after_create": False,
        "readback_verified": False,
        "cleanup_saved": False,
        "apply_after_cleanup": False,
        "restored_rule_count": None,
        "restored_exactly": False,
    }

    original: list[dict[str, Any]] = []
    wrote_test = False

    try:
        device = find_device(host, session_id, args.hostname)
        target_ip = str(device["ip"]).strip()

        original = get_parent_rules(host, session_id)
        report["original_rule_count"] = len(original)

        if any(str(rule.get("ip", "")).strip() == target_ip for rule in original):
            raise RuntimeError(
                "The selected device already has a Parent Control rule. "
                "Refusing to overwrite it during the transport test."
            )

        test_rule = {
            "enableRule": False,
            "ip": target_ip,
            "startTime": "00:00",
            "endTime": "01:00",
            "scheduleDays": "0",
        }
        test_rules = copy.deepcopy(original)
        test_rules.append(test_rule)

        write_command(host, 385, session_id, {"datas": test_rules})
        wrote_test = True
        report["writes_performed"] = True
        report["create_saved"] = True

        write_command(host, 20, session_id)
        report["apply_after_create"] = True

        after_create = get_parent_rules(host, session_id)
        report["readback_verified"] = any(
            rule.get("enableRule") is False
            and str(rule.get("ip", "")).strip() == target_ip
            and str(rule.get("startTime", "")) == "00:00"
            and str(rule.get("endTime", "")) == "01:00"
            and str(rule.get("scheduleDays", "")) == "0"
            for rule in after_create
        )
        if not report["readback_verified"]:
            raise RuntimeError(
                "Temporary disabled rule was not visible in cmd 385 readback."
            )

    except Exception as exc:
        report["error"] = str(exc)

    finally:
        if wrote_test:
            try:
                # The stock UI includes success=true when deleting a rule.
                write_command(
                    host,
                    385,
                    session_id,
                    {"datas": original, "success": True},
                )
                report["cleanup_saved"] = True

                write_command(host, 20, session_id)
                report["apply_after_cleanup"] = True

                restored = get_parent_rules(host, session_id)
                report["restored_rule_count"] = len(restored)
                report["restored_exactly"] = same_rules(restored, original)
                if not report["restored_exactly"]:
                    report["cleanup_warning"] = (
                        "Readback does not exactly match the original rule list."
                    )
            except Exception as cleanup_exc:
                report["cleanup_error"] = str(cleanup_exc)

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=True))
    else:
        print("Parent Control write-path test")
        print("=" * 52)
        for key, value in report.items():
            print(f"{key:24} {value}")

    return 0 if report.get("restored_exactly") else 5


if __name__ == "__main__":
    raise SystemExit(main())
