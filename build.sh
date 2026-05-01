#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/CodexQuota.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

swiftc "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -o "$MACOS/CodexQuota"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

echo "$APP"
