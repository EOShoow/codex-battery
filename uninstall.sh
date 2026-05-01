#!/usr/bin/env bash
set -euo pipefail

LABEL="local.codex.quota.menu"
APP="$HOME/Applications/CodexQuota.app"
PLIST="$HOME/Library/LaunchAgents/local.codex.quota.menu.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP"

echo "Uninstalled CodexQuota"

