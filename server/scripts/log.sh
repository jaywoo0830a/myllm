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