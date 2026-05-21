#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="$REPO_ROOT/bin/watch_battery"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "watch_battery binary not found. Run ./scripts/build-watch-battery.sh first." >&2
  exit 1
fi

exec "$BIN_PATH" "$@"
