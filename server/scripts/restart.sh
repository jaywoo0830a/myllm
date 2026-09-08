#!/usr/bin/env bash
# -------------------------------------------------
# restart.sh – clean stop‑start of the Mistral server
#   Usage: restart.sh [model_slug]
# -------------------------------------------------
set -euo pipefail

# Resolve script directory (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Model slug (default: mistral-large)
MODEL_SLUG="${1:-mistral-large}"

# -----------------------------------------------------------------
# 1) Stop any previous instance (pid file)
# -----------------------------------------------------------------
PID_FILE="${SCRIPT_DIR}/../run/${MODEL_SLUG}.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🔴 Stopping previous server (PID $PID)…"
        kill "$PID" 2>/dev/null || true
        # Give it a moment to terminate gracefully
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo "⚠️ Process $PID still alive – sending SIGKILL"
            kill -9 "$PID" 2>/dev/null || true
        fi
    else
        echo "⚠️ Process $PID not running – cleaning up stale PID file"
    fi
    rm -f "$PID_FILE"
else
    echo "⚙️ No PID file found – assuming server not running"
fi

# -----------------------------------------------------------------
# 2) Start a fresh instance (detached)
# -----------------------------------------------------------------
UP_SCRIPT="${SCRIPT_DIR}/up.sh"

echo "🟢 Starting Mistral server (model: ${MODEL_SLUG})…"
bash "$UP_SCRIPT" "${MODEL_SLUG}"

# -----------------------------------------------------------------
# 3) Wait a moment for the server to bind the port
# -----------------------------------------------------------------
sleep 5

# -----------------------------------------------------------------
# 4) Health‑check
# -----------------------------------------------------------------
echo "🔎 Testing server endpoint …"
if bash "${SCRIPT_DIR}/test_server.sh" "${MODEL_SLUG}"; then
    echo "✅ Server is up and responding."
else
    echo "❌ Server test failed – see logs in run/*.log"
    exit 1
fi

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
