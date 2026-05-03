#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/CodexBattery.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
rm -rf "$HOME/Applications/CodexQuota.app"
mkdir -p "$MACOS"

swiftc "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -o "$MACOS/CodexBattery"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

echo "$APP"
