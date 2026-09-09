#!/usr/bin/env bash
# -------------------------------------------------
# restart.sh — clean stop-start of a llama-server
#   Usage: restart.sh [model_slug=parser]
# -------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_SLUG="${1:-parser}"

# 1) Stop any previous instance (pid file)
PID_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[DOWN] Stopping previous server (PID $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo "[WARN] Process $PID still alive - SIGKILL"
            kill -9 "$PID" 2>/dev/null || true
        fi
    else
        echo "[WARN] Process $PID not running - cleaning stale PID"
    fi
    rm -f "$PID_FILE"
else
    echo "[INFO] No PID file - assuming not running"
fi

# 2) Start fresh instance
bash "${SCRIPT_DIR}/up.sh" "${MODEL_SLUG}"

# 3) Wait for server to bind
sleep 5

# 4) Health-check
if bash "${SCRIPT_DIR}/test_server.sh" "${MODEL_SLUG}"; then
    echo "[OK] Server is up and responding."
else
    echo "[ERR] Server test failed - see run/*.log"
    exit 1
fi
