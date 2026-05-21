#!/usr/bin/env bash
set -euo pipefail

LABEL="${WATCH_BATTERY_AGENT_LABEL:-com.bluetoothembedded.watch-battery-monitor}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"

if [[ -f "$PLIST" ]]; then
    launchctl bootout "$GUI/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    echo "Removed launch agent $LABEL"
else
    echo "No launch agent found at $PLIST"
fi
