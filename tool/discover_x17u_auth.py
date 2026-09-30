#!/usr/bin/env python3
"""Authenticated, read-only discovery for MTN FlyX / Tozed ZLT X17U.

The script makes exactly one login attempt, prompts for the password locally,
never prints or saves the password, and only issues GET-style router commands.
It does not change router settings.
"""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import re
import secrets
import sys
import urllib.request
from typing import Any


def request_json(host: str, payload: dict[str, Any], timeout: float = 6.0) -> dict[str, Any]:
    url = f"http://{host}/cgi-bin/http.cgi"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "FlyX-Control-Authenticated-Discovery/0.2",
            "Referer": f"http://{host}/",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        parsed = json.loads(response.read().decode("utf-8", errors="replace") or "{}")
    if not isinstance(parsed, dict):
        raise ValueError("router returned a non-object JSON response")
    return parsed


def read_command(
    host: str,
    cmd: int,
    session_id: str = "",
    fields: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "cmd": cmd,
        "method": "GET",
        "sessionId": session_id,
    }
    if fields:
        payload.update(fields)
    result = request_json(host, payload)
    if result.get("success") is False:
        raise RuntimeError(f"cmd {cmd} refused: {result.get('message', 'unknown')}")
    return result


def login_once(host: str, username: str, password: str) -> str:
    challenge = read_command(host, 232)
    token = str(challenge.get("token", ""))
    if not token:
        raise RuntimeError("router did not return a login challenge token")

    requested_session = secrets.token_hex(32)
    digest = hashlib.sha256((token + password).encode("utf-8")).hexdigest()

    result = request_json(
        host,
        {
            "cmd": 100,
            "method": "POST",
            "username": username,
            "passwd": digest,
            "sessionId": requested_session,
            "isAutoUpgrade": "1",
            "isCheckPasswd": "1",
        },
    )

    if result.get("success") is not True:
        raise RuntimeError(
            "login rejected. Stop here and verify the password in the router web UI "
            "before trying again; repeated wrong attempts may trigger a lockout."
        )
    return str(result.get("sessionId") or requested_session)


def fingerprint(value: str, prefix: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]
    return f"{prefix}#{digest}"


def sanitize(value: Any, key: str = "") -> Any:
    normalized = re.sub(r"[^a-z0-9]", "", key.lower())

    if any(
        token in normalized
        for token in (
            "imei",
            "imsi",
            "iccid",
            "serial",
            "devicesn",
            "modulesn",
            "msisdn",
            "password",
            "passwd",
            "wpa",
            "key",
        )
    ):
        return "[redacted]" if str(value) else value

    if "mac" in normalized and str(value):
        return fingerprint(str(value).lower(), "mac")

    if normalized in {"ip", "ipaddr", "ipaddress"} and str(value):
        text = str(value)
        if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", text):
            parts = text.split(".")
            return ".".join(parts[:3] + ["x"])
        return "[redacted-ip]"

    if normalized in {"ipv6", "ipv6ip", "ipv6address"} and str(value):
        return "[redacted-ipv6]"

    if isinstance(value, dict):
        return {str(k): sanitize(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(item, key) for item in value]
    return value


def list_len(payload: dict[str, Any], key: str) -> int | None:
    value = payload.get(key)
    return len(value) if isinstance(value, list) else None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Authenticated read-only X17U discovery"
    )
    parser.add_argument("--host", default="192.168.0.1")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    host = (
        args.host.replace("http://", "")
        .replace("https://", "")
        .split("#", 1)[0]
        .rstrip("/")
    )

    password = getpass.getpass(
        "FlyX admin password (input is hidden; it is not saved): "
    )
    if not password:
        print("No password entered.", file=sys.stderr)
        return 2

    try:
        session_id = login_once(host, args.username, password)
    except Exception as exc:
        print(f"Login failed: {exc}", file=sys.stderr)
        return 3
    finally:
        password = ""

    # All commands below are GET/read probes. No configuration is changed.
    #
    # 223/402  connected-client sources
    # 224/225  2.4/5 GHz Wi-Fi association detail
    # 18       WAN flow counters on some X17U firmware
    # 337      traffic-plan/monthly usage data
    # 401      dashboard/WAN data on related firmware
    # 207      CPU/RAM/temperature on related firmware
    # 25       possible per-client speed-policy structure on related firmware
    # 23       MAC filter rules. The stock UI explicitly sends getfun=true.
    # 28/30    filter-mode related reads
    # 278      wireless filter endpoint used by the stock UI
    # 350      USSD state/read endpoint
    # 355      alternate traffic-flow endpoint
    probes: tuple[tuple[int, dict[str, Any]], ...] = (
        (223, {}),
        (224, {}),
        (225, {}),
        (402, {}),
        (18, {}),
        (337, {}),
        (401, {}),
        (207, {}),
        (25, {}),
        (23, {"getfun": True}),
        (28, {}),
        (30, {}),
        (278, {}),
        (350, {}),
        (355, {}),
    )
    commands = tuple(cmd for cmd, _ in probes)

    responses: dict[str, Any] = {}
    errors: dict[str, str] = {}

    for cmd, fields in probes:
        try:
            responses[str(cmd)] = read_command(
                host,
                cmd,
                session_id,
                fields=fields,
            )
        except Exception as exc:
            errors[str(cmd)] = str(exc)

    # The stock UI's Wi-Fi blacklist/whitelist component uses command 278
    # with subcmd "0" for 5 GHz and subcmd "1" for 2.4 GHz.
    for label, subcmd in (("278_5g", "0"), ("278_24g", "1")):
        try:
            responses[label] = read_command(
                host,
                278,
                session_id,
                fields={"subcmd": subcmd},
            )
        except Exception as exc:
            errors[label] = str(exc)

    d223 = responses.get("223", {})
    d402 = responses.get("402", {})
    d224 = responses.get("224", {})
    d225 = responses.get("225", {})
    d337 = responses.get("337", {})
    d25 = responses.get("25", {})
    d23 = responses.get("23", {})
    d278 = responses.get("278", {})
    d278_5g = responses.get("278_5g", {})
    d278_24g = responses.get("278_24g", {})
    d350 = responses.get("350", {})
    d355 = responses.get("355", {})

    device_rows = d223.get("dhcp_list_info")
    if not isinstance(device_rows, list):
        device_rows = d402.get("dhcp_list_info")

    filter_rows = d23.get("datas")

    report = {
        "host": host,
        "detected_api": "tozed-http-cgi",
        "authenticated": True,
        "read_only": True,
        "commands_tested": list(commands),
        "commands_ok": [int(cmd) for cmd in responses],
        "errors": errors,
        "capabilities": {
            "connected_device_list": isinstance(device_rows, list),
            "connected_device_count": len(device_rows) if isinstance(device_rows, list) else None,
            "wifi_24_client_detail": isinstance(d224.get("wlan24g_wifi_info"), list),
            "wifi_24_client_count": list_len(d224, "wlan24g_wifi_info"),
            "wifi_5_client_detail": isinstance(d225.get("wlan5g_wifi_info"), list),
            "wifi_5_client_count": list_len(d225, "wlan5g_wifi_info"),
            "monthly_usage_fields": any(
                key in d337
                for key in ("mon_download_flow", "dl_mon_flow", "ul_mon_flow", "limitSize")
            ),
            "possible_speed_policy_structure": len(d25) > 2,
            "filter_rule_list": isinstance(filter_rows, list),
            "filter_rule_count": len(filter_rows) if isinstance(filter_rows, list) else None,
            "filter_mode_detail": (
                isinstance(responses.get("28", {}).get("datas"), list)
                or isinstance(responses.get("30", {}).get("datas"), list)
            ),
            "wireless_filter_fields": sorted(
                key for key in d278.keys()
                if key not in {"success", "cmd", "message"}
            ),
            "wifi_5_filter_readable": isinstance(
                d278_5g.get("datas"), dict
            ),
            "wifi_5_filter_mode": (
                d278_5g.get("datas", {}).get("macfilter")
                if isinstance(d278_5g.get("datas"), dict)
                else None
            ),
            "wifi_5_filter_count": (
                len(d278_5g.get("datas", {}).get("maclist", []))
                if isinstance(d278_5g.get("datas"), dict)
                and isinstance(d278_5g.get("datas", {}).get("maclist"), list)
                else None
            ),
            "wifi_24_filter_readable": isinstance(
                d278_24g.get("datas"), dict
            ),
            "wifi_24_filter_mode": (
                d278_24g.get("datas", {}).get("macfilter")
                if isinstance(d278_24g.get("datas"), dict)
                else None
            ),
            "wifi_24_filter_count": (
                len(d278_24g.get("datas", {}).get("maclist", []))
                if isinstance(d278_24g.get("datas"), dict)
                and isinstance(d278_24g.get("datas", {}).get("maclist"), list)
                else None
            ),
            "ussd_fields": sorted(
                key for key in d350.keys()
                if key not in {"success", "cmd", "message"}
            ),
            "alternate_flow_fields": sorted(
                key for key in d355.keys()
                if key not in {"success", "cmd", "message"}
            ),
        },
        "responses": sanitize(responses),
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    print("FlyX authenticated read-only discovery")
    print("=" * 52)
    for name, value in report["capabilities"].items():
        print(f"{name:31} {value}")
    if errors:
        print(f"\nRead errors: {errors}")
    print("\nNo router settings were changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
