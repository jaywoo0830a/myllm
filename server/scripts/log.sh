#!/usr/bin/env bash
# ============================================================
# log.sh — Show the latest log output for a llama-server
#   Usage: log.sh [--follow] <model_slug> [lines]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FOLLOW=false
if [[ "$1" == "--follow" ]]; then
    FOLLOW=true
    shift
fi
MODEL_SLUG="${1:-parser}"
LINES="${2:-50}"
LOG_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.log"

print_header() { echo "=== $1 of $LOG_FILE ==="; }

if [[ ! -f "$LOG_FILE" ]]; then
    echo "[ERR] Log file not found for model $MODEL_SLUG"
    exit 1
fi

if $FOLLOW; then
    print_header "Real-time tail"
    tail -F "$LOG_FILE"
else
    print_header "Last $LINES lines"
    tail -n "$LINES" "$LOG_FILE"
fi
