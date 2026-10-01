#!/usr/bin/env python3
"""Configure a generated Flutter Android project for stable FlyX beta signing.

The private keystore is supplied only through GitHub Actions secrets. Nothing
secret is committed to the repository. If the secret is absent, the script
leaves Flutter's normal debug signing untouched.
"""
from __future__ import annotations

import base64
import os
from pathlib import Path
import sys


def main() -> int:
    encoded = os.environ.get("FLYX_BETA_KEYSTORE_B64", "").strip()
    store_password = os.environ.get("FLYX_BETA_STORE_PASSWORD", "")
    key_alias = os.environ.get("FLYX_BETA_KEY_ALIAS", "")
    key_password = os.environ.get("FLYX_BETA_KEY_PASSWORD", "")

    if not encoded:
        print("Stable beta signing is not configured; keeping debug signing.")
        return 0

    missing = [
        name
        for name, value in (
            ("FLYX_BETA_STORE_PASSWORD", store_password),
            ("FLYX_BETA_KEY_ALIAS", key_alias),
            ("FLYX_BETA_KEY_PASSWORD", key_password),
        )
        if not value
    ]
    if missing:
        print(
            "Stable beta signing is partially configured; missing: "
            + ", ".join(missing),
            file=sys.stderr,
        )
        return 2

    app_dir = Path("android/app")
    gradle = app_dir / "build.gradle.kts"
    if not gradle.exists():
        print("android/app/build.gradle.kts was not generated.", file=sys.stderr)
        return 3

    try:
        keystore_bytes = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        print(f"Invalid FLYX_BETA_KEYSTORE_B64: {exc}", file=sys.stderr)
        return 4

    keystore = app_dir / "flyx-beta.jks"
    keystore.write_bytes(keystore_bytes)

    text = gradle.read_text(encoding="utf-8")
    marker = "    buildTypes {"
    if marker not in text:
        print("Could not locate Android buildTypes block.", file=sys.stderr)
        return 5

    signing_block = """    signingConfigs {
        create("flyxBeta") {
            storeFile = file("flyx-beta.jks")
            storePassword = System.getenv("FLYX_BETA_STORE_PASSWORD")
            keyAlias = System.getenv("FLYX_BETA_KEY_ALIAS")
            keyPassword = System.getenv("FLYX_BETA_KEY_PASSWORD")
        }
    }

"""

    if 'create("flyxBeta")' not in text:
        text = text.replace(marker, signing_block + marker, 1)

    debug_line = '            signingConfig = signingConfigs.getByName("debug")'
    release_line = '            signingConfig = signingConfigs.getByName("flyxBeta")'
    if debug_line in text:
        text = text.replace(debug_line, release_line, 1)
    elif release_line not in text:
        print("Could not locate Flutter release signing line.", file=sys.stderr)
        return 6

    gradle.write_text(text, encoding="utf-8")
    print("Configured stable FlyX beta release signing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
