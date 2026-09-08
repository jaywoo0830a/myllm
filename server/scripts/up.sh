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
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null
# Tuning parameters for optimal performance on AMD 9700X + DDR5 64 GB
export THREADS=8               # one thread per physical core
export KV_CACHE="q8_0"         # KV‑Cache quantisation for a small speed boost

# Start the server using the existing llama_serve_mistral.sh script
bash "$SCRIPT_DIR/llama_serve_mistral.sh" &
SERVER_PID=$!
echo "Mistral server started with PID $SERVER_PID for slug $MODEL_SLUG"
echo "$SERVER_PID" > "$SCRIPT_DIR/../run/${MODEL_SLUG}.pid"