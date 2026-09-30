#!/usr/bin/env python3
"""Read-only inspection of the X17U stock web UI.

Version 0.2 is more tolerant of router front-ends that do not place ordinary
<script src="..."> tags on /. It follows same-origin HTML/iframe/meta-refresh
references, discovers JS-like URLs from script/link/src/href attributes and
quoted strings, and records small sanitized previews of entry documents.

No login is performed and no router command is sent.
"""
from __future__ import annotations

import argparse
import gzip
import html
import json
import re
import sys
import urllib.parse
import urllib.request
import zlib
from collections import deque
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
    r"setMACData",
    r"setMACMode",
    r"getMACData",
    r"getWirelessFilter",
    r"setWirelessFilter",
    r"acceptAll",
    r"enableRule",
    r"ippro",
    r"downlinkSpeedLimit",
    r"uplinkSpeedLimit",
]

ATTR_RE = re.compile(
    r"""\b(?:src|href)\s*=\s*["']([^"'#]+)["']""",
    re.IGNORECASE,
)
QUOTED_ASSET_RE = re.compile(
    r"""["']([^"'\s<>]+\.(?:js|mjs|cjs|html?|css)(?:\?[^"'\s<>]*)?)["']""",
    re.IGNORECASE,
)
META_REFRESH_RE = re.compile(
    r"""<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*?url\s*=\s*([^"';>]+)""",
    re.IGNORECASE,
)
IFRAME_RE = re.compile(
    r"""<iframe\b[^>]*src\s*=\s*["']([^"']+)["']""",
    re.IGNORECASE,
)

ROUTE_CHUNK_RE = re.compile(
    r"""path\s*:\s*["']([^"']+)["'](?:(?!\}\s*,\s*\{).){0,900}?
        name\s*:\s*["']([^"']+)["'](?:(?!\}\s*,\s*\{).){0,900}?
        n\.e\(["']([^"']+)["']\)""",
    re.IGNORECASE | re.DOTALL | re.VERBOSE,
)
CHUNK_CALL_RE = re.compile(
    r"""n\.e\(["'](chunk-[A-Za-z0-9_-]+)["']\)"""
)
CHUNK_HASH_RE = re.compile(
    r"""["'](chunk-[A-Za-z0-9_-]+)["']\s*:\s*["']([0-9a-fA-F]{6,32})["']"""
)
TARGET_ROUTE_WORDS = (
    "mac",
    "filter",
    "accesscontrol",
    "speed",
    "client",
    "device",
    "firewall",
)

ENTRY_PATHS = (
    "/",
    "/index.html",
    "/index.htm",
    "/login.html",
    "/main.html",
    "/home.html",
    "/web/index.html",
)


def fetch_text(url: str, timeout: float = 8.0) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "FlyX-Control-UI-Inspector/0.3",
            "Accept": "text/html,application/javascript,text/javascript,text/css,*/*",
            "Accept-Encoding": "identity",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read()
        encoding = (response.headers.get("Content-Encoding") or "").lower()

        # Some X17U firmware serves gzip-compressed HTML without a usable
        # Content-Encoding header. Detect the payload itself as well.
        decoded = raw
        compression = "none"
        try:
            if raw.startswith(b"\x1f\x8b"):
                decoded = gzip.decompress(raw)
                compression = "gzip-magic"
            elif encoding == "gzip":
                decoded = gzip.decompress(raw)
                compression = "gzip-header"
            elif encoding == "deflate":
                try:
                    decoded = zlib.decompress(raw)
                except zlib.error:
                    decoded = zlib.decompress(raw, -zlib.MAX_WBITS)
                compression = "deflate"
        except Exception:
            # Preserve the original bytes for reporting instead of failing the
            # whole inspection if a router returns malformed compressed data.
            decoded = raw
            compression = "decode-failed"

        return {
            "url": response.geturl(),
            "content_type": response.headers.get_content_type(),
            "status": getattr(response, "status", 200),
            "raw": raw,
            "decoded_bytes": len(decoded),
            "compression": compression,
            "text": decoded.decode("utf-8", errors="replace"),
        }


def compact_snippet(text: str, start: int, end: int, radius: int = 260) -> str:
    lo = max(0, start - radius)
    hi = min(len(text), end + radius)
    snippet = html.unescape(text[lo:hi])
    snippet = re.sub(r"\s+", " ", snippet)
    return sanitize_text(snippet.strip())


def sanitize_text(text: str) -> str:
    text = re.sub(
        r"(?i)\b(?:imei|imsi|iccid|serial|device[_-]?sn|module[_-]?sn)\b\s*[:=]\s*['\"]?[^,'\"}\s<]+",
        "[redacted-identifier]",
        text,
    )
    text = re.sub(
        r"\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b",
        "[redacted-mac]",
        text,
    )
    text = re.sub(
        r"\b(?:\d{1,3}\.){3}\d{1,3}\b",
        "[redacted-ip]",
        text,
    )
    return text


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
            if len(hits) >= 100:
                return hits
    return hits


def same_origin(base_host: str, url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme in ("", "http", "https") and (
        not parsed.netloc or parsed.hostname == base_host
    )


def discover_refs(base_url: str, text: str) -> list[str]:
    refs: list[str] = []

    def add(value: str) -> None:
        value = html.unescape(value.strip())
        if not value or value.startswith(("data:", "javascript:", "mailto:", "tel:")):
            return
        url = urllib.parse.urljoin(base_url, value)
        if url not in refs:
            refs.append(url)

    for value in ATTR_RE.findall(text):
        add(value)
    for value in IFRAME_RE.findall(text):
        add(value)
    for value in META_REFRESH_RE.findall(text):
        add(value)
    for value in QUOTED_ASSET_RE.findall(text):
        add(value)

    return refs


def preview(text: str, limit: int = 1600) -> str:
    cleaned = re.sub(r"\s+", " ", html.unescape(text)).strip()
    return sanitize_text(cleaned[:limit])


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Read-only X17U stock web UI inspector"
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

    queue: deque[str] = deque()
    for path in ENTRY_PATHS:
        queue.append(urllib.parse.urljoin(base, path))

    seen_urls: set[str] = set()
    discovered_refs: set[str] = set()
    entry_documents: list[dict[str, Any]] = []
    assets: list[dict[str, Any]] = []
    errors: dict[str, str] = {}

    total_downloaded = 0
    max_total = 30 * 1024 * 1024
    max_urls = 120
    app_js_text = ""

    while queue and len(seen_urls) < max_urls and total_downloaded < max_total:
        url = queue.popleft()
        url = url.split("#", 1)[0]
        if url in seen_urls or not same_origin(host, url):
            continue
        seen_urls.add(url)

        try:
            result = fetch_text(url)
        except Exception as exc:
            errors[url] = str(exc)
            continue

        raw = result["raw"]
        text = result["text"]
        size = len(raw)
        total_downloaded += size
        content_type = result["content_type"]
        final_url = result["url"]

        is_html = (
            "html" in content_type
            or "<html" in text[:1000].lower()
            or "<!doctype" in text[:1000].lower()
        )
        is_scriptish = (
            "javascript" in content_type
            or final_url.lower().split("?", 1)[0].endswith((".js", ".mjs", ".cjs"))
        )

        if urllib.parse.urlparse(final_url).path == "/js/app.js":
            app_js_text = text

        hits = inspect_asset(text)
        if hits:
            assets.append(
                {
                    "asset": urllib.parse.urlparse(final_url).path or "/",
                    "content_type": content_type,
                    "bytes": size,
                    "hits": hits,
                }
            )

        if is_html:
            entry_documents.append(
                {
                    "requested": urllib.parse.urlparse(url).path or "/",
                    "final_url": final_url,
                    "status": result["status"],
                    "content_type": content_type,
                    "bytes": size,
                    "decoded_bytes": result.get("decoded_bytes", size),
                    "compression": result.get("compression", "none"),
                    "preview": preview(text),
                }
            )

        if is_html or is_scriptish:
            for ref in discover_refs(final_url, text):
                if not same_origin(host, ref):
                    continue
                clean = ref.split("#", 1)[0]
                discovered_refs.add(clean)

                path = urllib.parse.urlparse(clean).path.lower()
                if (
                    path.endswith((".js", ".mjs", ".cjs", ".html", ".htm"))
                    or "javascript" in clean.lower()
                    or path.endswith("/")
                ):
                    if clean not in seen_urls:
                        queue.append(clean)

    script_refs = sorted(
        ref
        for ref in discovered_refs
        if urllib.parse.urlparse(ref).path.lower().endswith((".js", ".mjs", ".cjs"))
    )

    # Vue/Webpack lazy-loaded route chunks are not always present as literal
    # script URLs in index.html. Resolve the route chunk name + hash map from
    # app.js and fetch only the high-value network-control chunks.
    route_chunks: list[dict[str, str]] = []
    chunk_hashes: dict[str, str] = {}
    lazy_chunk_attempts: list[dict[str, Any]] = []

    if app_js_text:
        for match in ROUTE_CHUNK_RE.finditer(app_js_text):
            path, name, chunk = match.groups()
            route_chunks.append(
                {"path": path, "name": name, "chunk": chunk}
            )

        chunk_hashes = {
            chunk: digest
            for chunk, digest in CHUNK_HASH_RE.findall(app_js_text)
        }

        target_chunks: set[str] = set()
        for route in route_chunks:
            searchable = (route["path"] + " " + route["name"]).lower()
            compact = re.sub(r"[^a-z0-9]", "", searchable)
            if any(word in compact for word in TARGET_ROUTE_WORDS):
                target_chunks.add(route["chunk"])

        # If route parsing misses a minified edge case, still include chunks
        # mentioned near known control keywords.
        for keyword in (
            "macFilter",
            "accessControl",
            "speedLimit",
            "Attached Devices",
            "Filtering Rules",
        ):
            start = 0
            while True:
                pos = app_js_text.find(keyword, start)
                if pos < 0:
                    break
                window = app_js_text[max(0, pos - 1200):pos + 1200]
                target_chunks.update(CHUNK_CALL_RE.findall(window))
                start = pos + len(keyword)

        for chunk in sorted(target_chunks):
            candidates: list[str] = []
            digest = chunk_hashes.get(chunk)
            if digest:
                candidates.append(
                    urllib.parse.urljoin(base, f"js/{chunk}.{digest}.js")
                )
            candidates.append(
                urllib.parse.urljoin(base, f"js/{chunk}.js")
            )

            fetched = False
            last_error = ""
            for candidate in candidates:
                if candidate in seen_urls:
                    continue
                try:
                    result = fetch_text(candidate)
                    fetched = True
                    seen_urls.add(candidate)
                    raw = result["raw"]
                    text = result["text"]
                    total_downloaded += len(raw)
                    hits = inspect_asset(text)

                    if hits:
                        assets.append(
                            {
                                "asset": urllib.parse.urlparse(
                                    result["url"]
                                ).path,
                                "content_type": result["content_type"],
                                "bytes": len(raw),
                                "hits": hits,
                            }
                        )

                    lazy_chunk_attempts.append(
                        {
                            "chunk": chunk,
                            "url": candidate,
                            "fetched": True,
                            "bytes": len(raw),
                            "hits": len(hits),
                        }
                    )
                    break
                except Exception as exc:
                    last_error = str(exc)

            if not fetched:
                lazy_chunk_attempts.append(
                    {
                        "chunk": chunk,
                        "fetched": False,
                        "hash_found": digest is not None,
                        "error": last_error or "no candidate URL succeeded",
                    }
                )

    report = {
        "host": host,
        "read_only": True,
        "login_attempted": False,
        "router_commands_sent": False,
        "version": "0.4",
        "urls_fetched": len(seen_urls),
        "script_assets_found": len(script_refs),
        "all_references_found": len(discovered_refs),
        "assets_with_relevant_hits": len(assets),
        "downloaded_bytes": total_downloaded,
        "entry_documents": entry_documents,
        "script_refs": [
            urllib.parse.urlparse(ref).path for ref in script_refs[:100]
        ],
        "route_chunks": route_chunks,
        "chunk_hashes_found": len(chunk_hashes),
        "lazy_chunk_attempts": lazy_chunk_attempts,
        "errors": errors,
        "assets": assets,
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=True))
    else:
        print("X17U stock UI inspection")
        print("=" * 52)
        print(f"URLs fetched:       {len(seen_urls)}")
        print(f"References found:   {len(discovered_refs)}")
        print(f"JS assets found:    {len(script_refs)}")
        print(f"Relevant assets:    {len(assets)}")
        print(f"Route chunks:       {len(route_chunks)}")
        print(f"Lazy chunks tried:  {len(lazy_chunk_attempts)}")
        for doc in entry_documents[:8]:
            print(
                f"\n{doc['requested']} -> {doc['final_url']} "
                f"({doc['content_type']}, {doc['bytes']} bytes)"
            )
            print(f"  {doc['preview'][:500]}")
        for asset in assets:
            print(f"\n{asset['asset']}")
            for hit in asset["hits"][:12]:
                print(f"  [{hit['pattern']}] {hit['snippet']}")
        print("\nNo login or router command was performed.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
