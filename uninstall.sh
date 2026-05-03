#!/usr/bin/env bash
set -euo pipefail

LABEL="local.codex.battery.menu"
OLD_LABEL="local.codex.quota.menu"
APP="$HOME/Applications/CodexBattery.app"
OLD_APP="$HOME/Applications/CodexQuota.app"
PLIST="$HOME/Library/LaunchAgents/local.codex.battery.menu.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/local.codex.quota.menu.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$OLD_PLIST"
rm -rf "$APP"
rm -rf "$OLD_APP"

echo "Uninstalled Codex Battery"
