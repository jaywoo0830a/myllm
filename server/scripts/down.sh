#!/usr/bin/env bash
# ============================================================
# down.sh — Stop a running llama-server
#   Usage: down.sh <model_slug>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_SLUG="${1:-parser}"
PID_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.pid"

if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[DOWN] Stopping llama-server (PID $PID) for model $MODEL_SLUG"
        kill "$PID" 2>/dev/null || true
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo "[WARN] Process $PID still alive - sending SIGKILL"
            kill -9 "$PID" 2>/dev/null || true
        fi
    else
        echo "[WARN] Process $PID not running - cleaning up stale PID file"
    fi
    rm -f "$PID_FILE"
else
    echo "[ERR] No PID file found for model $MODEL_SLUG. Is the server running?"
fi
