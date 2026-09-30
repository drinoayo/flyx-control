#!/usr/bin/env python3
"""Read-only FlyX / ZLT X17U capability discovery.

No settings are changed. The script only reads reqproc keys and public JS files
served by the router UI. It is useful before enabling firmware-specific writes.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request


def get_text(url: str, timeout: float = 4.0) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "Referer": url.split("/", 3)[:3][0] if False else url,
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "FlyX-Control-Discovery/0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def read_cmd(host: str, commands: list[str]) -> dict:
    query = {"isTest": "false", "cmd": ",".join(commands)}
    if len(commands) > 1:
        query["multi_data"] = "1"
    url = f"http://{host}/reqproc/proc_get?{urllib.parse.urlencode(query)}"
    return json.loads(get_text(url))


def main() -> int:
    parser = argparse.ArgumentParser(description="Safe read-only discovery for MTN FlyX / ZLT X17U")
    parser.add_argument("--host", default="192.168.0.1", help="Router address (default: 192.168.0.1)")
    parser.add_argument("--json", action="store_true", help="Print JSON only")
    args = parser.parse_args()
    host = args.host.replace("http://", "").replace("https://", "").rstrip("/")

    keys = [
        "network_type",
        "rssi",
        "signalbar",
        "lte_rsrq",
        "lte_pci",
        "ppp_status",
        "station_list",
        "cr_version",
        "tz_customer_code",
        "psw_fail_num_str",
        "login_lock_time",
    ]

    try:
        status = read_cmd(host, keys)
    except Exception as exc:
        print(f"Could not reach http://{host}: {exc}", file=sys.stderr)
        return 2

    source = ""
    readable_scripts = []
    for path in ("/js/service.js", "/js/config/ufi/config.js", "/js/util.js"):
        try:
            text = get_text(f"http://{host}{path}")
            source += "\n" + text
            readable_scripts.append(path)
        except Exception:
            pass

    actions = set(re.findall(r"goformId\s*[:=]\s*[\"']([A-Z0-9_]+)[\"']", source))
    for value in re.findall(r"[\"']([A-Z][A-Z0-9_]{4,})[\"']", source):
        if any(token in value for token in ("SMS", "USSD", "WIFI", "REBOOT", "TRAFFIC_BLOCK", "BEARER")):
            actions.add(value)

    report = {
        "host": host,
        "status": status,
        "readable_scripts": readable_scripts,
        "actions": sorted(actions),
        "capabilities": {
            "station_list": bool(status.get("station_list")),
            "sms": "SEND_SMS" in actions,
            "ussd": "USSD_PROCESS" in actions,
            "wifi_settings": "SET_WIFI_SSID1_SETTINGS" in actions,
            "reboot": "REBOOT_DEVICE" in actions,
            "network_mode": "SET_BEARER_PREFERENCE" in actions,
            "known_traffic_block_action": "AIRTEL_SET_TRAFFIC_BLOCK" in actions,
        },
    }

    if args.json:
        print(json.dumps(report, indent=2))
        return 0

    print("FlyX / X17U discovery")
    print("=" * 44)
    print(f"Router:       {host}")
    print(f"Firmware:     {status.get('cr_version') or 'not exposed'}")
    print(f"Network:      {status.get('network_type') or 'unknown'}")
    print(f"RSSI:         {status.get('rssi') or 'unknown'}")
    print(f"Stations:     {'available' if status.get('station_list') else 'not returned'}")
    print(f"UI scripts:   {len(readable_scripts)} readable")
    print(f"Actions:      {len(actions)} discovered")
    print("\nInteresting actions")
    interesting = [a for a in sorted(actions) if any(t in a for t in ("SMS", "USSD", "WIFI", "REBOOT", "BLOCK", "BEARER"))]
    for action in interesting:
        print(f"  - {action}")
    print("\nNo router settings were changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
