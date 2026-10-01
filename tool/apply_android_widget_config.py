#!/usr/bin/env python3
"""Apply FlyX home-screen widget files to a generated Android scaffold."""
from __future__ import annotations

from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
PATCH_SOURCE = ROOT / "platform_patches/android/app"
PATCH_TARGET = ROOT / "android/app"


def main() -> int:
    if not MANIFEST.exists():
        raise SystemExit(
            "Android scaffold is missing. Run 'flutter create . --platforms=android' first."
        )
    if not PATCH_SOURCE.exists():
        raise SystemExit("FlyX Android widget patch files are missing.")

    text = MANIFEST.read_text(encoding="utf-8")
    if ".FlyxWidgetProvider" not in text:
        widget_components = """
        <activity
            android:name=".FlyxWidgetConfigActivity"
            android:exported="true"
            android:theme="@style/FlyxWidgetConfigTheme">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_CONFIGURE" />
            </intent-filter>
        </activity>
        <receiver
            android:name=".FlyxWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/flyx_widget_info" />
        </receiver>
"""
        marker = "    </application>"
        if marker not in text:
            raise SystemExit("Could not locate </application> in AndroidManifest.xml.")
        text = text.replace(marker, widget_components + marker, 1)
        MANIFEST.write_text(text, encoding="utf-8")

    shutil.copytree(PATCH_SOURCE, PATCH_TARGET, dirs_exist_ok=True)
    print("Applied FlyX Android home-screen widget configuration.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
