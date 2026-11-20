#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
destination="$HOME/Applications"
if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || $1 != --output-dir || -z $2 ]]; then
    echo "Usage: $0 [--output-dir DIRECTORY]" >&2
    exit 2
  fi
  destination="$2"
fi
mkdir -p "$destination"
stage="$(mktemp -d "$destination/.codex-battery-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
APP="$stage/CodexBattery.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

compiler=(swiftc "$ROOT"/Sources/*.swift -framework AppKit)
for prefix in "${ZSTD_PREFIX:-}" /opt/homebrew/opt/zstd /usr/local/opt/zstd; do
  if [[ -n "$prefix" && -f "$prefix/include/zstd.h" && -f "$prefix/lib/libzstd.a" && -f "$prefix/LICENSE" ]] &&
     lipo -verify_arch "$(uname -m)" "$prefix/lib/libzstd.a" >/dev/null 2>&1; then
    compiler+=(-D CODEX_BATTERY_ZSTD -import-objc-header "$prefix/include/zstd.h" "$prefix/lib/libzstd.a")
    cp "$prefix/LICENSE" "$RESOURCES/LICENSE-zstd"
    break
  fi
done
if [[ ! -f "$RESOURCES/LICENSE-zstd" ]]; then
  echo "Building without zstd. Compressed Claude Desktop usage entries require zstd at build time." >&2
fi
"${compiler[@]}" -o "$MACOS/CodexBattery"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/CodexBattery.icns" "$RESOURCES/CodexBattery.icns"
cp "$ROOT/Resources/task_runner.py" "$RESOURCES/task_runner.py"

# Seal the complete local bundle after copying resources; this is not Developer ID signing.
codesign --force --sign - "$APP"

rm -rf "$destination/CodexBattery.app"
mv "$APP" "$destination/CodexBattery.app"
if [[ $# -eq 0 ]]; then rm -rf "$destination/CodexQuota.app"; fi
echo "$destination/CodexBattery.app"
