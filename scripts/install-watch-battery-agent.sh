#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITOR_SCRIPT="$REPO_ROOT/scripts/watch-battery-monitor.sh"
LABEL="${WATCH_BATTERY_AGENT_LABEL:-com.bluetoothembedded.watch-battery-monitor}"
INTERVAL="${WATCH_BATTERY_AGENT_INTERVAL_SECONDS:-600}"
STATE_DIR="${WATCH_BATTERY_STATE_DIR:-$HOME/Library/Caches/watch-battery-monitor}"
LOW_THRESHOLD="${WATCH_BATTERY_LOW_THRESHOLD:-20}"
FAST_DROP_RATE="${WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR:-12}"
LOW_BATTERY_COOLDOWN="${WATCH_BATTERY_LOW_COOLDOWN_MINUTES:-30}"
FAST_DROP_COOLDOWN="${WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES:-30}"
LAUNCHD_PATH="${WATCH_BATTERY_LAUNCHD_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"

usage() {
    cat <<'USAGE'
Usage: install-watch-battery-agent.sh --iphone <udid> [options]

Options:
  --iphone <udid>                    iPhone UDID that owns the Watch
  --label <label>                     LaunchAgent label (default: com.bluetoothembedded.watch-battery-monitor)
  --interval <seconds>                Poll interval (default: 600)
  --low-threshold <0-100>             Low battery threshold (default: 20)
  --fast-drop-rate <percent/hour>     Fast drain threshold (default: 12)
  --low-cooldown-minutes <minutes>    Low alert cooldown (default: 30)
  --fast-cooldown-minutes <minutes>   Fast drain alert cooldown (default: 30)
  --help                              Show this message
USAGE
}

if ! command -v launchctl >/dev/null 2>&1; then
    echo "launchctl is required" >&2
    exit 1
fi

if ! JQ_PATH="$(command -v jq 2>/dev/null)"; then
    echo "jq is required. Install it with: brew install jq" >&2
    exit 1
fi

JQ_DIR="$(dirname "$JQ_PATH")"
case ":$LAUNCHD_PATH:" in
    *":$JQ_DIR:"*) ;;
    *) LAUNCHD_PATH="$JQ_DIR:$LAUNCHD_PATH" ;;
esac

if ! [[ -x "$MONITOR_SCRIPT" ]]; then
    echo "monitor script missing: $MONITOR_SCRIPT" >&2
    exit 1
fi

iphone_udid=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iphone)
            shift
            iphone_udid="$1"
            ;;
        --label)
            shift
            LABEL="$1"
            ;;
        --interval)
            shift
            INTERVAL="$1"
            ;;
        --low-threshold)
            shift
            LOW_THRESHOLD="$1"
            ;;
        --fast-drop-rate)
            shift
            FAST_DROP_RATE="$1"
            ;;
        --low-cooldown-minutes)
            shift
            LOW_BATTERY_COOLDOWN="$1"
            ;;
        --fast-cooldown-minutes)
            shift
            FAST_DROP_COOLDOWN="$1"
            ;;
        --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            if [[ -z "$iphone_udid" ]]; then
                iphone_udid="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ -z "$iphone_udid" ]]; then
    echo "Missing --iphone <udid>" >&2
    usage
    exit 1
fi

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    printf '%s' "$s"
}

require_integer() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$name must be a non-negative integer (got: $value)" >&2
        exit 1
    fi
}

require_label() {
    local value="$1"
    if ! [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "--label must match [A-Za-z0-9._-]+ (got: $value)" >&2
        exit 1
    fi
}

require_udid() {
    local value="$1"
    if ! [[ "$value" =~ ^[A-Za-z0-9-]+$ ]]; then
        echo "--iphone UDID must match [A-Za-z0-9-]+ (got: $value)" >&2
        exit 1
    fi
}

require_label "$LABEL"
require_udid "$iphone_udid"
require_integer "--interval" "$INTERVAL"
require_integer "--low-threshold" "$LOW_THRESHOLD"
require_integer "--fast-drop-rate" "$FAST_DROP_RATE"
require_integer "--low-cooldown-minutes" "$LOW_BATTERY_COOLDOWN"
require_integer "--fast-cooldown-minutes" "$FAST_DROP_COOLDOWN"

LABEL_X="$(xml_escape "$LABEL")"
IPHONE_UDID_X="$(xml_escape "$iphone_udid")"
STATE_DIR_X="$(xml_escape "$STATE_DIR")"
MONITOR_SCRIPT_X="$(xml_escape "$MONITOR_SCRIPT")"
LAUNCHD_PATH_X="$(xml_escape "$LAUNCHD_PATH")"

mkdir -p "$STATE_DIR"
mkdir -p "$HOME/Library/LaunchAgents"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

cat > "$PLIST_PATH" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL_X</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$INTERVAL</integer>
    <key>StandardOutPath</key>
    <string>$STATE_DIR_X/monitor.log</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR_X/monitor.err</string>
    <key>ProgramArguments</key>
    <array>
        <string>$MONITOR_SCRIPT_X</string>
        <string>--iphone</string>
        <string>$IPHONE_UDID_X</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$LAUNCHD_PATH_X</string>
        <key>WATCH_BATTERY_LOW_THRESHOLD</key>
        <string>$LOW_THRESHOLD</string>
        <key>WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR</key>
        <string>$FAST_DROP_RATE</string>
        <key>WATCH_BATTERY_LOW_COOLDOWN_MINUTES</key>
        <string>$LOW_BATTERY_COOLDOWN</string>
        <key>WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES</key>
        <string>$FAST_DROP_COOLDOWN</string>
        <key>WATCH_BATTERY_STATE_DIR</key>
        <string>$STATE_DIR_X</string>
        <key>WATCH_BATTERY_STATE_FILE</key>
        <string>$STATE_DIR_X/state.json</string>
    </dict>
</dict>
</plist>
EOF_PLIST

BOOTSTRAP_GUI="gui/$(id -u)"
launchctl bootout "$BOOTSTRAP_GUI/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$BOOTSTRAP_GUI" "$PLIST_PATH"

echo "Installed launch agent: $PLIST_PATH"
echo "Label: $LABEL"
echo "Interval: ${INTERVAL}s"
echo "To disable: launchctl bootout $BOOTSTRAP_GUI/$LABEL"
