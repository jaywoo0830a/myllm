#!/usr/bin/env bash
# ============================================================
# test_server.sh — Simple health‑check for the running llama‑server
#   Usage: test_server.sh <model_slug>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MODEL_SLUG="${1:-mistral-large}"
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null

ENDPOINT="http://${LLAMA_HOST}:${LLAMA_PORT}/v1/models"
echo "Testing endpoint $ENDPOINT ..."
curl -s -m 5 "$ENDPOINT" | head -n 5 || {
  echo "❌ Server not reachable or returned error."
  exit 1
}
echo "✅ Server responded successfully."