#!/usr/bin/env bash
# ============================================================
# down.sh — Stop a running Mistral server
#   Usage: down.sh <model_slug>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/../run/${1:-mistral-large}.pid"

if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "Stopped Mistral server with PID $PID"
    rm -f "$PID_FILE"
  else
    echo "Process $PID not running"
    rm -f "$PID_FILE"
  fi
else
  echo "No PID file found for model ${1:-mistral-large}. Is the server running?"
fi