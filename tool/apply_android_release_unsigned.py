#!/usr/bin/env python3
"""Make the generated Android release build unsigned before CI packaging.

FlyX Control release APKs are signed outside CI with the permanent owner-held
keystore. Debug builds keep Flutter's normal debug signing.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KTS = ROOT / "android/app/build.gradle.kts"
GROOVY = ROOT / "android/app/build.gradle"


def main() -> int:
    path = KTS if KTS.exists() else GROOVY
    if not path.exists():
        raise SystemExit("Generated Android app Gradle file was not found.")

    text = path.read_text(encoding="utf-8")
    original = text

    if path.suffix == ".kts":
        text = text.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = null',
        )
    else:
        text = text.replace(
            "signingConfig signingConfigs.debug",
            "signingConfig null",
        )

    if text == original:
        raise SystemExit(
            "Could not find Flutter's generated release debug-signing line."
        )

    path.write_text(text, encoding="utf-8")
    print("Configured Android release build as unsigned for owner signing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
