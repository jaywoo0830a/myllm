#!/usr/bin/env bash
# -------------------------------------------------
# restart.sh – clean stop‑start of the Mistral server
# -------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------
# 1) Stop any previous instance (pid file)
# -----------------------------------------------------------------
PIDFILE="../run/mistral-large.pid"
if [[ -f "$PIDFILE" ]]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" >/dev/null 2>&1; then
        echo "🔴 Stopping previous server (PID $PID)…"
        kill "$PID" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
fi

# -----------------------------------------------------------------
# 2) Start a fresh instance (detached)
# -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP_SCRIPT="${SCRIPT_DIR}/up.sh"

echo "🟢 Starting Mistral server (model: mistral-large)…"
bash "$UP_SCRIPT" mistral-large

# -----------------------------------------------------------------
# 3) Wait a moment for the server to bind the port
# -----------------------------------------------------------------
sleep 5

# -----------------------------------------------------------------
# 4) Health‑check
# -----------------------------------------------------------------
echo "🔎 Testing server endpoint …"
if bash "$SCRIPT_DIR/test_server.sh" mistral-large; then
    echo "✅ Server is up and responding."
else
    echo "❌ Server test failed – see logs in run/*.log"
    exit 1
fi
