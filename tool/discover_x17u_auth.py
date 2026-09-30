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
import urllib.error
import urllib.request
from typing import Any


def request_json(host: str, payload: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    url = f"http://{host}/cgi-bin/http.cgi"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "FlyX-Control-Authenticated-Discovery/0.1",
            "Referer": f"http://{host}/",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        parsed = json.loads(response.read().decode("utf-8", errors="replace") or "{}")
    if not isinstance(parsed, dict):
        raise ValueError("router returned a non-object JSON response")
    return parsed


def read_command(host: str, cmd: int, session_id: str = "") -> dict[str, Any]:
    result = request_json(
        host,
        {"cmd": cmd, "method": "GET", "sessionId": session_id},
    )
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

    if any(token in normalized for token in ("imei", "imsi", "iccid", "serial", "devicesn", "modulesn", "msisdn", "password", "passwd")):
        return "[redacted]" if str(value) else value

    if "mac" in normalized and str(value):
        return fingerprint(str(value).lower(), "mac")

    if normalized in {"ip", "ipaddr", "ipaddress"} and str(value):
        text = str(value)
        if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", text):
            parts = text.split(".")
            return ".".join(parts[:3] + ["x"])
        return "[redacted-ip]"

    if isinstance(value, dict):
        return {str(k): sanitize(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(item, key) for item in value]
    return value


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

    # Known read-only authenticated calls from the current X17U mapping.
    commands = (223, 23, 28, 30)
    responses: dict[str, Any] = {}
    errors: dict[str, str] = {}

    for cmd in commands:
        try:
            responses[str(cmd)] = read_command(host, cmd, session_id)
        except Exception as exc:
            errors[str(cmd)] = str(exc)

    device_rows = responses.get("223", {}).get("dhcp_list_info")
    filter_rows = responses.get("23", {}).get("datas")

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
            "filter_rule_list": isinstance(filter_rows, list),
            "filter_rule_count": len(filter_rows) if isinstance(filter_rows, list) else None,
            "filter_mode_ipv4_ipv6": "28" in responses and "30" in responses,
        },
        "responses": sanitize(responses),
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    print("FlyX authenticated read-only discovery")
    print("=" * 48)
    print(f"Connected-device list: {report['capabilities']['connected_device_list']}")
    print(f"Connected devices:     {report['capabilities']['connected_device_count']}")
    print(f"Filter rules:          {report['capabilities']['filter_rule_list']}")
    print(f"Filter rule count:     {report['capabilities']['filter_rule_count']}")
    print(f"Filter modes readable: {report['capabilities']['filter_mode_ipv4_ipv6']}")
    print("\nNo router settings were changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
