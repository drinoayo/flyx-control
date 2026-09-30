#!/usr/bin/env python3
"""Read-only inspection of the X17U web UI JavaScript.

Downloads the router's public HTML/JS assets and searches them for references
that may reveal the exact command IDs and payload shapes used by the stock UI.

No login is performed and no router command is sent.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from typing import Any

PATTERNS = [
    r"mac[_-]?filter",
    r"blacklist",
    r"whitelist",
    r"block(?:ed)?[_ -]?device",
    r"access[_-]?control",
    r"speed[_-]?limit",
    r"bandwidth[_-]?limit",
    r"traffic[_-]?limit",
    r"flow[_-]?limit",
    r"per[_ -]?device",
    r"wlan24g_wifi_info",
    r"wlan5g_wifi_info",
    r"dhcp_list_info",
    r"LIMITED_ACCESS",
    r"cmd\s*[:=]\s*23\b",
    r"cmd\s*[:=]\s*25\b",
    r"cmd\s*[:=]\s*28\b",
    r"cmd\s*[:=]\s*30\b",
    r"cmd\s*[:=]\s*223\b",
    r"cmd\s*[:=]\s*224\b",
    r"cmd\s*[:=]\s*225\b",
    r"cmd\s*[:=]\s*337\b",
    r"cmd\s*[:=]\s*401\b",
    r"cmd\s*[:=]\s*402\b",
]

SCRIPT_RE = re.compile(
    r"<script\b[^>]*?src=[\"']([^\"']+)[\"'][^>]*?>",
    re.IGNORECASE,
)


def fetch_text(url: str, timeout: float = 8.0) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "FlyX-Control-UI-Inspector/0.1",
            "Accept": "text/html,application/javascript,text/javascript,*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read()
    return raw.decode("utf-8", errors="replace")


def compact_snippet(text: str, start: int, end: int, radius: int = 260) -> str:
    lo = max(0, start - radius)
    hi = min(len(text), end + radius)
    snippet = text[lo:hi]
    snippet = html.unescape(snippet)
    snippet = re.sub(r"\s+", " ", snippet)
    return snippet.strip()


def inspect_asset(text: str) -> list[dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    seen: set[str] = set()

    for pattern in PATTERNS:
        regex = re.compile(pattern, re.IGNORECASE)
        for match in regex.finditer(text):
            snippet = compact_snippet(text, match.start(), match.end())
            signature = pattern + "|" + snippet
            if signature in seen:
                continue
            seen.add(signature)
            hits.append({"pattern": pattern, "snippet": snippet})
            if len(hits) >= 80:
                return hits
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read-only X17U stock web UI JavaScript inspector"
    )
    parser.add_argument("--host", default="192.168.0.1")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    host = (
        args.host.replace("http://", "")
        .replace("https://", "")
        .split("#", 1)[0]
        .rstrip("/")
    )
    base = f"http://{host}/"

    try:
        index = fetch_text(base)
    except Exception as exc:
        print(f"Could not read {base}: {exc}", file=sys.stderr)
        return 2

    script_urls = []
    for src in SCRIPT_RE.findall(index):
        url = urllib.parse.urljoin(base, src)
        if url not in script_urls:
            script_urls.append(url)

    assets: list[dict[str, Any]] = []
    index_hits = inspect_asset(index)
    if index_hits:
        assets.append(
            {
                "asset": "/",
                "bytes": len(index.encode("utf-8")),
                "hits": index_hits,
            }
        )

    errors: dict[str, str] = {}
    total_downloaded = 0
    max_total = 30 * 1024 * 1024

    for url in script_urls:
        if total_downloaded >= max_total:
            errors[url] = "skipped after 30 MiB inspection limit"
            continue
        try:
            text = fetch_text(url)
            size = len(text.encode("utf-8"))
            total_downloaded += size
            hits = inspect_asset(text)
            if hits:
                assets.append(
                    {
                        "asset": urllib.parse.urlparse(url).path,
                        "bytes": size,
                        "hits": hits,
                    }
                )
        except Exception as exc:
            errors[url] = str(exc)

    report = {
        "host": host,
        "read_only": True,
        "login_attempted": False,
        "router_commands_sent": False,
        "script_assets_found": len(script_urls),
        "assets_with_relevant_hits": len(assets),
        "downloaded_bytes": total_downloaded,
        "errors": errors,
        "assets": assets,
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print("X17U stock UI inspection")
        print("=" * 48)
        print(f"Scripts found: {len(script_urls)}")
        print(f"Relevant assets: {len(assets)}")
        for asset in assets:
            print(f"\n{asset['asset']}")
            for hit in asset["hits"][:12]:
                print(f"  [{hit['pattern']}] {hit['snippet']}")
        print("\nNo login or router command was performed.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
