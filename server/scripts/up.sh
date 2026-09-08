#!/usr/bin/env bash
# ============================================================
# up.sh — Start the Mistral server in the background
#   Usage: up.sh <model_slug>
# ============================================================
set -euo pipefail

# Resolve script directory (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# -----------------------------------------------------------------
# Model slug (default: mistral-large)
# -----------------------------------------------------------------
MODEL_SLUG="${1:-mistral-large}"
export MODEL_SLUG

# Load environments – abort if they cannot be loaded
load_base_env
load_model_env "${MODEL_SLUG}" >/dev/null

# -----------------------------------------------------------------
# Performance tuning (override via env if needed)
# -----------------------------------------------------------------
export THREADS="${THREADS:-8}"      # one thread per physical core
export KV_CACHE="${KV_CACHE:-q8_0}" # KV‑Cache quantisation

# -----------------------------------------------------------------
# Prepare run directory and log file (absolute paths)
# -----------------------------------------------------------------
RUN_DIR="${SCRIPT_DIR}/../run"
mkdir -p "${RUN_DIR}"
LOG_FILE="${RUN_DIR}/${MODEL_SLUG}.log"
PID_FILE="${RUN_DIR}/${MODEL_SLUG}.pid"

# Ensure we can write to the log file before starting the server
if ! touch "${LOG_FILE}" 2>/dev/null; then
    echo "❌ Cannot write to log file ${LOG_FILE}. Check permissions." >&2
    exit 1
fi

# -----------------------------------------------------------------
# Start the server in background, capture stdout+stderr to log
# -----------------------------------------------------------------
nohup "${SCRIPT_DIR}/llama_serve_mistral.sh" &> "${LOG_FILE}" &
SERVER_PID=$!

# Give the process a moment to start and write its PID file
sleep 1
if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "❌ Server failed to start. See ${LOG_FILE} for details." >&2
    exit 1
fi

# Record PID atomically
printf "%s\n" "${SERVER_PID}" > "${PID_FILE}"

echo "✅ Mistral server started (PID ${SERVER_PID}) for model ${MODEL_SLUG}"
echo "🗒️ Log file: ${LOG_FILE}"

