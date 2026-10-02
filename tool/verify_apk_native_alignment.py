#!/usr/bin/env python3
"""Verify that uncompressed Android native libraries stay page-aligned.

Release signing must preserve the alignment padding produced by the Android
build tools. Repacking an APK can strip that padding and cause Android to
reject the APK with INSTALL_FAILED_INVALID_APK while extracting native libs.
"""
from __future__ import annotations

import struct
import sys
import zipfile
from pathlib import Path

PAGE_ALIGNMENT = 16 * 1024


def local_data_offset(handle, info: zipfile.ZipInfo) -> int:
    handle.seek(info.header_offset)
    header = handle.read(30)
    if len(header) != 30:
        raise RuntimeError(f"Truncated local header: {info.filename}")
    values = struct.unpack("<IHHHHHIIIHH", header)
    signature = values[0]
    if signature != 0x04034B50:
        raise RuntimeError(f"Invalid local header: {info.filename}")
    name_length = values[-2]
    extra_length = values[-1]
    return info.header_offset + 30 + name_length + extra_length


def verify(apk: Path) -> None:
    failures: list[str] = []
    checked = 0

    with apk.open("rb") as handle, zipfile.ZipFile(apk) as archive:
        for info in archive.infolist():
            if not (info.filename.startswith("lib/") and info.filename.endswith(".so")):
                continue
            if info.compress_type != zipfile.ZIP_STORED:
                continue
            checked += 1
            offset = local_data_offset(handle, info)
            if offset % PAGE_ALIGNMENT != 0:
                failures.append(
                    f"{info.filename}: data offset {offset} is not "
                    f"{PAGE_ALIGNMENT}-byte aligned"
                )

    if checked == 0:
        raise SystemExit("No uncompressed native libraries were found to verify.")
    if failures:
        raise SystemExit(
            "Native library alignment check failed:\n- " + "\n- ".join(failures)
        )

    print(
        f"Native library alignment OK: {checked} uncompressed .so files are "
        f"{PAGE_ALIGNMENT}-byte aligned."
    )


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_apk_native_alignment.py <apk>")
    verify(Path(sys.argv[1]).resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
