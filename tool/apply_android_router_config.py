#!/usr/bin/env python3
"""Apply FlyX local-router networking settings to generated Android files."""
from __future__ import annotations

from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
NETWORK_SOURCE = ROOT / "platform_patches/android/network_security_config.xml"
NETWORK_TARGET = ROOT / "android/app/src/main/res/xml/network_security_config.xml"


def main() -> int:
    if not MANIFEST.exists():
        raise SystemExit(
            "Android scaffold is missing. Run 'flutter create . --platforms=android' first."
        )

    text = MANIFEST.read_text(encoding="utf-8")

    permissions = [
        '    <uses-permission android:name="android.permission.INTERNET" />',
        '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
    ]
    missing = [line for line in permissions if line not in text]
    if missing:
        marker = ">"
        manifest_pos = text.find(marker, text.find("<manifest"))
        if manifest_pos == -1:
            raise SystemExit("Could not locate the <manifest> opening tag.")
        insertion = "\n" + "\n".join(missing)
        text = text[: manifest_pos + 1] + insertion + text[manifest_pos + 1 :]

    text = text.replace(
        'android:label="flyx_control"',
        'android:label="FlyX Control"',
    )

    if 'android:usesCleartextTraffic="true"' not in text:
        text = text.replace(
            "<application",
            '<application\n        android:usesCleartextTraffic="true"',
            1,
        )

    if 'android:networkSecurityConfig="@xml/network_security_config"' not in text:
        text = text.replace(
            'android:usesCleartextTraffic="true"',
            'android:usesCleartextTraffic="true"\n        '
            'android:networkSecurityConfig="@xml/network_security_config"',
            1,
        )

    MANIFEST.write_text(text, encoding="utf-8")

    NETWORK_TARGET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(NETWORK_SOURCE, NETWORK_TARGET)

    print("Applied Android local-router network configuration.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
