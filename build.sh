#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/CodexBattery.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
rm -rf "$HOME/Applications/CodexQuota.app"
mkdir -p "$MACOS" "$RESOURCES"

swiftc "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -o "$MACOS/CodexBattery"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/CodexBattery.icns" "$RESOURCES/CodexBattery.icns"

echo "$APP"
