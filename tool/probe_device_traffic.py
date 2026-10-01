#!/usr/bin/env python3
"""Read-only per-device traffic discovery for MTN FlyX / ZLT X17U.

The probe compares an idle phase with an active-traffic phase for one connected
device. It never changes router configuration. Private MAC/IP/session values are
used only in memory to match the selected device and are not written to the
report.
"""
from __future__ import annotations

import argparse
import getpass
import json
import sys
import time
from collections import defaultdict
from typing import Any

from discover_x17u_auth import login_once, read_command

SENSITIVE_KEYS = {
    "mac",
    "macaddr",
    "ip",
    "ipaddr",
    "hostname",
    "sessionid",
    "token",
    "imei",
    "imsi",
    "iccid",
    "serial",
    "devicesn",
    "modulesn",
    "cmei",
    "eid",
}


def text(value: Any) -> str:
    return str(value if value is not None else "").strip()


def normalise_mac(value: Any) -> str:
    chars = "".join(ch for ch in text(value) if ch.lower() in "0123456789abcdef")
    if len(chars) != 12:
        return ""
    return ":".join(chars[i : i + 2].upper() for i in range(0, 12, 2))


def safe_scalar_map(row: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in row.items():
        k = str(key)
        if k.lower() in SENSITIVE_KEYS:
            continue
        if isinstance(value, (str, int, float, bool)) or value is None:
            result[k] = value
    return result


def find_matching_rows(
    value: Any,
    *,
    target_mac: str,
    target_ip: str,
    target_hostname: str,
    path: str = "$",
) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []

    if isinstance(value, dict):
        row_mac = normalise_mac(value.get("mac") or value.get("macaddr"))
        row_ip = text(value.get("ip") or value.get("ipaddr"))
        row_host = text(value.get("hostname"))

        matches = (
            (target_mac and row_mac == target_mac)
            or (target_ip and row_ip == target_ip)
            or (
                target_hostname
                and row_host.lower() == target_hostname.lower()
            )
        )
        if matches:
            found.append(
                {
                    "path": path,
                    "fields": safe_scalar_map(value),
                }
            )

        for key, child in value.items():
            found.extend(
                find_matching_rows(
                    child,
                    target_mac=target_mac,
                    target_ip=target_ip,
                    target_hostname=target_hostname,
                    path=f"{path}.{key}",
                )
            )
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(
                find_matching_rows(
                    child,
                    target_mac=target_mac,
                    target_ip=target_ip,
                    target_hostname=target_hostname,
                    path=f"{path}[{index}]",
                )
            )

    return found


def safe_cmd355(payload: dict[str, Any]) -> dict[str, Any]:
    """Keep only structural/scalar data and strip identifiers recursively."""

    def clean(value: Any, key_hint: str = "") -> Any:
        if key_hint.lower() in SENSITIVE_KEYS:
            return "[redacted]"
        if isinstance(value, dict):
            return {
                str(key): clean(child, str(key))
                for key, child in value.items()
                if str(key).lower() not in SENSITIVE_KEYS
            }
        if isinstance(value, list):
            return [clean(child) for child in value[:50]]
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        return str(value)

    return clean(payload)


def read_target(host: str, session_id: str, hostname: str) -> tuple[str, str]:
    payload = read_command(host, 223, session_id)
    rows = payload.get("dhcp_list_info")
    if not isinstance(rows, list):
        raise RuntimeError("cmd 223 did not return a connected-device list")

    matches = [
        row
        for row in rows
        if isinstance(row, dict)
        and text(row.get("hostname")).lower() == hostname.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one connected device named {hostname!r}; "
            f"found {len(matches)}."
        )

    mac = normalise_mac(matches[0].get("mac"))
    ip = text(matches[0].get("ip"))
    if not mac or not ip:
        raise RuntimeError("Selected device is missing a usable MAC or LAN IP.")
    return mac, ip


def sample(
    host: str,
    session_id: str,
    *,
    hostname: str,
    target_mac: str,
    target_ip: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for cmd in (223, 224, 225, 402, 355):
        try:
            payload = read_command(host, cmd, session_id)
            entry: dict[str, Any] = {
                "matched_rows": find_matching_rows(
                    payload,
                    target_mac=target_mac,
                    target_ip=target_ip,
                    target_hostname=hostname,
                )
            }
            if cmd == 355:
                entry["safe_payload"] = safe_cmd355(payload)
            result[str(cmd)] = entry
        except Exception as exc:
            result[str(cmd)] = {"error": str(exc)}
    return result


def flatten_numeric(value: Any, prefix: str = "") -> dict[str, float]:
    output: dict[str, float] = {}
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            output.update(flatten_numeric(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            path = f"{prefix}[{index}]"
            output.update(flatten_numeric(child, path))
    elif isinstance(value, bool):
        pass
    elif isinstance(value, (int, float)):
        output[prefix] = float(value)
    elif isinstance(value, str):
        try:
            number = float(value)
        except ValueError:
            pass
        else:
            output[prefix] = number
    return output


def summarize_phase(samples: list[dict[str, Any]]) -> dict[str, Any]:
    series: dict[str, list[float]] = defaultdict(list)
    for item in samples:
        for path, number in flatten_numeric(item).items():
            series[path].append(number)

    changed: dict[str, Any] = {}
    for path, values in series.items():
        if len(values) < 2:
            continue
        minimum = min(values)
        maximum = max(values)
        if maximum == minimum:
            continue
        changed[path] = {
            "first": values[0],
            "last": values[-1],
            "min": minimum,
            "max": maximum,
            "delta": values[-1] - values[0],
            "changes": sum(
                1 for left, right in zip(values, values[1:]) if left != right
            ),
        }
    return changed


def collect_phase(
    host: str,
    session_id: str,
    *,
    hostname: str,
    target_mac: str,
    target_ip: str,
    samples: int,
    interval: float,
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for index in range(samples):
        output.append(
            sample(
                host,
                session_id,
                hostname=hostname,
                target_mac=target_mac,
                target_ip=target_ip,
            )
        )
        if index + 1 < samples:
            time.sleep(interval)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read-only per-device traffic discovery probe"
    )
    parser.add_argument("--host", default="192.168.0.1")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    host = (
        args.host.replace("http://", "")
        .replace("https://", "")
        .split("#", 1)[0]
        .rstrip("/")
    )

    password = getpass.getpass("FlyX admin password (hidden; not saved): ")
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

    try:
        target_mac, target_ip = read_target(
            host,
            session_id,
            args.hostname,
        )
    except Exception as exc:
        print(f"Target lookup failed: {exc}", file=sys.stderr)
        return 4

    print(
        "Phase 1/2: leave the selected device mostly idle. "
        "Sampling now...",
        file=sys.stderr,
    )
    idle = collect_phase(
        host,
        session_id,
        hostname=args.hostname,
        target_mac=target_mac,
        target_ip=target_ip,
        samples=max(2, args.samples),
        interval=max(0.5, args.interval),
    )

    print(
        "Phase 2/2: on the selected device, start a large download, "
        "high-quality video, or speed test. Then press ENTER here: ",
        file=sys.stderr,
        end="",
        flush=True,
    )
    input()

    active = collect_phase(
        host,
        session_id,
        hostname=args.hostname,
        target_mac=target_mac,
        target_ip=target_ip,
        samples=max(2, args.samples),
        interval=max(0.5, args.interval),
    )

    report = {
        "test": "per-device-traffic-read-only",
        "read_only": True,
        "target_hostname": args.hostname,
        "target_identifiers": "[used only in memory; not saved]",
        "sample_interval_seconds": max(0.5, args.interval),
        "samples_per_phase": max(2, args.samples),
        "idle_changed_numeric_fields": summarize_phase(idle),
        "active_changed_numeric_fields": summarize_phase(active),
        "idle_samples": idle,
        "active_samples": active,
    }

    print(json.dumps(report, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
