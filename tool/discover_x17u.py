#!/usr/bin/env python3
"""Read-only discovery for MTN FlyX / Tozed ZLT X17U.

This script performs only unauthenticated GET-style API reads through the X17U's
JSON RPC endpoint. It never logs in and never changes router settings.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from typing import Any


SENSITIVE_KEYS = {
    "imei",
    "imsi",
    "iccid",
    "msisdn",
    "serial",
    "serialnumber",
    "sn",
    "mac",
    "macaddr",
    "macaddress",
    "wifipassword",
    "wifi_password",
    "password",
    "passwd",
    "key",
}


def post_command(host: str, cmd: int, timeout: float = 5.0) -> dict[str, Any]:
    url = f"http://{host}/cgi-bin/http.cgi"
    body = json.dumps(
        {
            "cmd": cmd,
            "method": "GET",
            "sessionId": "",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "FlyX-Control-Discovery/0.2",
            "Referer": f"http://{host}/",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8", errors="replace")
    parsed = json.loads(raw or "{}")
    if not isinstance(parsed, dict):
        raise ValueError(f"cmd {cmd} returned a non-object JSON response")
    return parsed


def sanitize(value: Any, key: str = "") -> Any:
    normalized = key.lower().replace("-", "").replace("_", "")
    if (
        normalized in SENSITIVE_KEYS
        or normalized.endswith("sn")
        or any(
            token in normalized
            for token in (
                "imei",
                "imsi",
                "iccid",
                "serial",
                "wifipassword",
                "password",
                "passwd",
            )
        )
    ):
        text = str(value)
        if not text:
            return value
        if len(text) <= 4:
            return "[redacted]"
        return f"[redacted:{text[-4:]}]"

    if "mac" in normalized and str(value):
        return "[redacted-mac]"

    if isinstance(value, dict):
        return {str(k): sanitize(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(item, key) for item in value]
    return value


def has_success(payload: dict[str, Any]) -> bool:
    if payload.get("success") is True:
        return True
    # Some firmware builds return useful fields without a boolean success flag.
    return len(payload) > 1 or any(
        name in payload
        for name in (
            "uptime",
            "network_type_str",
            "wan_ip",
            "RSRP",
            "signal_lvl",
            "network_operator",
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Safe read-only discovery for MTN FlyX / Tozed ZLT X17U"
    )
    parser.add_argument(
        "--host",
        default="192.168.0.1",
        help="Router address (default: 192.168.0.1)",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON only")
    args = parser.parse_args()

    host = (
        args.host.replace("http://", "")
        .replace("https://", "")
        .split("#", 1)[0]
        .rstrip("/")
    )

    # Known safe, unauthenticated reads on this Tozed firmware family.
    # 113: liveness/basic status
    # 133: WAN, uptime, counters and core RF values
    # 205: richer RF/operator/monthly-flow information
    commands = (113, 133, 205)
    responses: dict[str, Any] = {}
    errors: dict[str, str] = {}

    for cmd in commands:
        try:
            responses[str(cmd)] = post_command(host, cmd)
        except urllib.error.HTTPError as exc:
            errors[str(cmd)] = f"HTTP {exc.code}: {exc.reason}"
        except Exception as exc:
            errors[str(cmd)] = str(exc)

    if not responses:
        print(
            f"Could not read the FlyX API at http://{host}/cgi-bin/http.cgi. "
            f"Results: {errors}",
            file=sys.stderr,
        )
        return 2

    wan = responses.get("133", {})
    rf = responses.get("205", {})
    live = responses.get("113", {})

    report = {
        "host": host,
        "detected_api": "tozed-http-cgi",
        "endpoint": "/cgi-bin/http.cgi",
        "read_only": True,
        "commands_tested": list(commands),
        "commands_ok": [
            int(cmd) for cmd, payload in responses.items() if has_success(payload)
        ],
        "errors": errors,
        "capabilities": {
            "liveness_read": bool(live),
            "wan_status_read": bool(wan),
            "rf_detail_read": bool(rf),
            "router_uptime_field": "uptime" in wan,
            "wan_byte_counters": (
                "wan_rx_bytes" in wan or "wan_tx_bytes" in wan
            ),
            "lte_signal_fields": any(
                key in wan for key in ("RSRP", "RSRQ", "SINR", "RSSI")
            ),
            "nr_signal_fields": any(
                key in wan for key in ("RSRP_5G", "SINR_5G", "RSRQ_5G")
            )
            or any(key in rf for key in ("currentband_5g", "PCI_5G", "FREQ_5G")),
            "monthly_flow_field": "mon_total_flow" in rf,
            "connected_devices": "requires authenticated discovery",
            "blocking": "requires authenticated discovery",
            "per_device_usage": "requires authenticated discovery",
        },
        "responses": sanitize(responses),
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    print("FlyX / X17U discovery")
    print("=" * 48)
    print(f"Router:        {host}")
    print("API:           POST /cgi-bin/http.cgi")
    print(f"Commands OK:   {report['commands_ok']}")
    print(f"Network:       {wan.get('network_type_str') or 'unknown'}")
    print(f"Uptime:        {wan.get('uptime') or 'not exposed'}")
    print(f"RSRP:          {wan.get('RSRP') or 'not exposed'}")
    print(f"RSRQ:          {wan.get('RSRQ') or 'not exposed'}")
    print(f"SINR:          {wan.get('SINR') or 'not exposed'}")
    print(f"LTE band:      {wan.get('currentband') or 'not exposed'}")
    print(f"5G band:       {rf.get('currentband_5g') or 'not exposed'}")
    print(f"Monthly flow:  {rf.get('mon_total_flow') or 'not exposed'}")
    if errors:
        print(f"Partial errors: {errors}")
    print("\nNo login was attempted and no router settings were changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
