#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/CodexBattery.app"
PLIST="$HOME/Library/LaunchAgents/local.codex.battery.menu.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/local.codex.quota.menu.plist"
LABEL="local.codex.battery.menu"
OLD_LABEL="local.codex.quota.menu"

"$ROOT/build.sh" >/dev/null

mkdir -p "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/CodexBattery" 2>/dev/null || true
rm -f "$OLD_PLIST"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP/Contents/MacOS/CodexBattery</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/CodexBattery.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/CodexBattery.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $APP"
echo "LaunchAgent: $PLIST"
