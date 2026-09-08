#!/usr/bin/env bash
# ============================================================
# log.sh — Show the latest log output for a Mistral server
#   Usage: log.sh [--follow] <model_slug> [lines]
# ============================================================
set -euo pipefail

# Resolve script directory (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------
# Parse arguments – optional --follow flag for real‑time tail
# -----------------------------------------------------------------
FOLLOW=false
if [[ "$1" == "--follow" ]]; then
    FOLLOW=true
    shift
fi
MODEL_SLUG="${1:-mistral-large}"
LINES="${2:-50}"
LOG_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.log"

# -----------------------------------------------------------------
# Helper to print a helpful header
# -----------------------------------------------------------------
print_header() {
    echo "=== $1 of $LOG_FILE ==="
}

if [[ ! -f "$LOG_FILE" ]]; then
    echo "❌ Log file not found for model $MODEL_SLUG"
    exit 1
fi

if $FOLLOW; then
    # Real‑time follow (Ctrl‑C to stop)
    print_header "Real‑time tail"
    tail -F "$LOG_FILE"
else
    # Static view – last N lines
    print_header "Last $LINES lines"
    tail -n "$LINES" "$LOG_FILE"
fi

#!/usr/bin/env bash
# ============================================================
# log.sh — Show the latest log output for a Mistral server
#   Usage: log.sh <model_slug> [lines]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_SLUG="${1:-mistral-large}"
LINES="${2:-50}"
LOG_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.log"

if [[ -f "$LOG_FILE" ]]; then
  echo "=== Last $LINES lines of $LOG_FILE ==="
  tail -n "$LINES" "$LOG_FILE"
else
  echo "Log file not found for model $MODEL_SLUG"
fi