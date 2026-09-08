#!/usr/bin/env bash
# ============================================================
# up.sh — Start the Mistral server in the background
#   Usage: up.sh <model_slug>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

MODEL_SLUG="${1:-mistral-large}"
export MODEL_SLUG
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null
# Tuning parameters for optimal performance on AMD 9700X + DDR5 64 GB
export THREADS=8               # one thread per physical core
export KV_CACHE="q8_0"         # KV‑Cache quantisation for a small speed boost

# Ensure the run directory exists (in case init was not run)
RUN_DIR="${SCRIPT_DIR}/../run"
mkdir -p "$RUN_DIR"

# Log file path (log.sh expects ../run/<model>.log)
LOG_FILE="${RUN_DIR}/${MODEL_SLUG}.log"

# Run the server in background, capture stdout+stderr to log
#   - `nohup` keeps the process alive after the terminal closes.
#   - `&>` redirects both stdout and stderr to the log file.
#   - `&` puts it in the background.
nohup "$SCRIPT_DIR/llama_serve_mistral.sh" &> "$LOG_FILE" &
SERVER_PID=$!

echo "Mistral server started with PID $SERVER_PID for slug $MODEL_SLUG"
echo "Log file: $LOG_FILE"
echo "$SERVER_PID" > "${RUN_DIR}/${MODEL_SLUG}.pid"
