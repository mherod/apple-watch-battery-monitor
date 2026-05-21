#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCH_BATTERY_BIN="${WATCH_BATTERY_BIN:-$REPO_ROOT/bin/watch_battery}"
STATE_DIR="${WATCH_BATTERY_STATE_DIR:-$HOME/Library/Caches/watch-battery-monitor}"
STATE_FILE="${WATCH_BATTERY_STATE_FILE:-$STATE_DIR/state.json}"
LOG_FILE="${WATCH_BATTERY_LOG_FILE:-$STATE_DIR/monitor.log}"
LOW_THRESHOLD="${WATCH_BATTERY_LOW_THRESHOLD:-20}"
FAST_DROP_RATE="${WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR:-12}" # percent/hour
FAST_DROP_COOLDOWN_MINUTES="${WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES:-30}"
LOW_BATTERY_COOLDOWN_MINUTES="${WATCH_BATTERY_LOW_COOLDOWN_MINUTES:-30}"
MIN_SAMPLE_SECONDS="${WATCH_BATTERY_MIN_SAMPLE_SECONDS:-300}"

usage() {
    cat <<'USAGE'
Usage: watch-battery-monitor.sh --iphone <iphone_udid> [options]

Options:
  --iphone <udid>                     iPhone UDID that owns the Watch
  --low-threshold <0-100>             Notify below this percent (default: 20)
  --fast-drop-rate <percent/hour>      Alert if drain exceeds this rate (default: 12)
  --fast-cooldown-minutes <minutes>    Cooldown for fast-drain alerts (default: 30)
  --low-cooldown-minutes <minutes>     Cooldown for low-battery alerts (default: 30)
  --state-file <path>                  Override state file path
  --help                               Show this message
USAGE
}

escape_osascript() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/\"/\\\"/g'
}

send_notification() {
    local title="$1"
    local subtitle="$2"
    local body="$3"
    local sound="${WATCH_BATTERY_ALERT_SOUND:-Glass}"

    local safe_title safe_subtitle safe_body
    safe_title=$(escape_osascript "$title")
    safe_subtitle=$(escape_osascript "$subtitle")
    safe_body=$(escape_osascript "$body")

    if ! command -v osascript >/dev/null 2>&1; then
        printf 'notification: %s | %s | %s\n' "$title" "$subtitle" "$body" >>"$LOG_FILE"
        return 0
    fi

    /usr/bin/osascript \
        -e "display notification \"$safe_body\" with title \"$safe_title\" subtitle \"$safe_subtitle\" sound name \"$sound\"" || true
}

if ! command -v jq >/dev/null 2>&1; then
    echo "watch-battery-monitor requires jq" >&2
    exit 1
fi

if ! command -v awk >/dev/null 2>&1; then
    echo "watch-battery-monitor requires awk" >&2
    exit 1
fi

if [[ ! -x "$WATCH_BATTERY_BIN" ]]; then
    echo "watch-battery executable not found: $WATCH_BATTERY_BIN" >&2
    echo "Run ./scripts/build-watch-battery.sh first." >&2
    exit 1
fi

mkdir -p "$STATE_DIR"

iPhone_udid=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iphone)
            shift
            iPhone_udid="${1:-}"
            ;;
        --low-threshold)
            shift
            LOW_THRESHOLD="${1:-$LOW_THRESHOLD}"
            ;;
        --fast-drop-rate)
            shift
            FAST_DROP_RATE="${1:-$FAST_DROP_RATE}"
            ;;
        --fast-cooldown-minutes)
            shift
            FAST_DROP_COOLDOWN_MINUTES="${1:-$FAST_DROP_COOLDOWN_MINUTES}"
            ;;
        --low-cooldown-minutes)
            shift
            LOW_BATTERY_COOLDOWN_MINUTES="${1:-$LOW_BATTERY_COOLDOWN_MINUTES}"
            ;;
        --state-file)
            shift
            STATE_FILE="${1:-$STATE_FILE}"
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
            if [[ -z "$iPhone_udid" ]]; then
                iPhone_udid="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage
                exit 1
            fi
            ;;
    esac
    shift
    done

if [[ -z "$iPhone_udid" ]]; then
    echo "Missing --iphone <udid>" >&2
    usage
    exit 1
fi

if ! [[ "$LOW_THRESHOLD" =~ ^[0-9]+$ ]] || (( LOW_THRESHOLD < 0 || LOW_THRESHOLD > 100 )); then
    echo "Invalid --low-threshold value: $LOW_THRESHOLD" >&2
    exit 1
fi

if ! [[ "$FAST_DROP_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid --fast-drop-rate value: $FAST_DROP_RATE" >&2
    exit 1
fi

now_ts=$(date +%s)

if ! json_output="$("$WATCH_BATTERY_BIN" --watch-only --json "$iPhone_udid")"; then
    echo "watch_battery failed for iPhone $iPhone_udid" >&2
    exit 1
fi

if [[ -z "$json_output" ]]; then
    echo "No JSON returned from watch_battery" >&2
    exit 1
fi

watch_entry=$(jq -c '.devices[0] // empty' <<<"$json_output")
if [[ -z "$watch_entry" ]]; then
    echo "No watch found for iPhone $iPhone_udid" >&2
    exit 1
fi

watch_udid=$(jq -r '.udid // empty' <<<"$watch_entry")
watch_name=$(jq -r '.name // "Unknown Watch"' <<<"$watch_entry")
watch_battery=$(jq -r '.battery // empty' <<<"$watch_entry")
watch_charging=$(jq -r '.charging // false' <<<"$watch_entry")

if ! [[ "$watch_battery" =~ ^[0-9]+$ ]]; then
    echo "Invalid battery value: $watch_battery" >&2
    exit 1
fi

charging=0
if [[ "$watch_charging" == "true" || "$watch_charging" == "1" ]]; then
    charging=1
fi

prev_battery=""
prev_ts=0
prev_watch_udid=""
last_low_alert_at=0
last_fast_alert_at=0

if [[ -f "$STATE_FILE" ]]; then
    prev_battery=$(jq -r '.battery // empty' "$STATE_FILE")
    prev_ts=$(jq -r '.last_check // 0' "$STATE_FILE")
    prev_watch_udid=$(jq -r '.watch_udid // empty' "$STATE_FILE")
    last_low_alert_at=$(jq -r '.last_low_alert_at // 0' "$STATE_FILE")
    last_fast_alert_at=$(jq -r '.last_fast_alert_at // 0' "$STATE_FILE")
fi

low_alert_at="$last_low_alert_at"
fast_alert_at="$last_fast_alert_at"

if (( watch_battery <= LOW_THRESHOLD )) && (( !charging )); then
    if (( now_ts - last_low_alert_at >= LOW_BATTERY_COOLDOWN_MINUTES * 60 )); then
        send_notification "Watch battery low" "$watch_name" "Battery at ${watch_battery}% for ${watch_udid}."
        low_alert_at=$now_ts
    fi
fi

if [[ -n "$prev_battery" && "$prev_battery" =~ ^[0-9]+$ && -n "$prev_watch_udid" && "$prev_watch_udid" == "$watch_udid" ]]; then
    elapsed=$(( now_ts - prev_ts ))
    if (( elapsed >= MIN_SAMPLE_SECONDS && !charging && watch_battery < prev_battery )); then
        drop=$((prev_battery - watch_battery))
        drop_rate=$(awk -v drop="$drop" -v elapsed="$elapsed" 'BEGIN {printf "%.2f", (drop * 3600) / elapsed}')
        if awk -v rate="$drop_rate" -v threshold="$FAST_DROP_RATE" 'BEGIN {exit !(rate >= threshold)}'; then
            if (( now_ts - last_fast_alert_at >= FAST_DROP_COOLDOWN_MINUTES * 60 )); then
                send_notification "Watch battery dropping fast" "$watch_name" "Dropping ${drop}% over ${elapsed}s (~${drop_rate}%/hour)."
                fast_alert_at=$now_ts
            fi
        fi
    fi
fi

mkdir -p "$(dirname "$STATE_FILE")"
state_tmp=$(mktemp)
jq -n \
    --arg ts "$now_ts" \
    --arg watch_udid "$watch_udid" \
    --arg watch_name "$watch_name" \
    --arg battery "$watch_battery" \
    --argjson charging "$([ "$charging" -eq 1 ] && echo true || echo false)" \
    --argjson low_alert_at "$low_alert_at" \
    --argjson fast_alert_at "$fast_alert_at" \
    '{
      last_check: ($ts | tonumber),
      watch_udid: $watch_udid,
      watch_name: $watch_name,
      battery: ($battery | tonumber),
      charging: $charging,
      last_low_alert_at: $low_alert_at,
      last_fast_alert_at: $fast_alert_at
    }' >"$state_tmp"
mv "$state_tmp" "$STATE_FILE"

printf '%s\n' "$(date '+%F %T') watch=${watch_udid} battery=${watch_battery}%(charging=${charging}) low_alert=${low_alert_at} fast_alert=${fast_alert_at}" >>"$LOG_FILE"
