#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on PATH." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -R "$ROOT/lib" "$TMP/lib"
cp "$ROOT/pubspec.yaml" "$TMP/pubspec.yaml"
cp "$ROOT/analysis_options.yaml" "$TMP/analysis_options.yaml"

cd "$ROOT"
flutter create --project-name flyx_control --org com.flyxcontrol --platforms=android,ios .
rm -rf "$ROOT/lib"
cp -R "$TMP/lib" "$ROOT/lib"
cp "$TMP/pubspec.yaml" "$ROOT/pubspec.yaml"
cp "$TMP/analysis_options.yaml" "$ROOT/analysis_options.yaml"
python3 "$ROOT/tool/apply_android_router_config.py"
python3 "$ROOT/tool/apply_android_widget_config.py"
flutter pub get

echo
echo "Flutter platform shells generated and FlyX Android patches applied."
