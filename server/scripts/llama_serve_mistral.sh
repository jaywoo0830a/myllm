#!/usr/bin/env bash
# ============================================================
# llama_serve_mistral.sh
#   Mistral-Small-24B-Instruct-2501 (LLAMA architecture GGUF, autoregressive) model
#   Serves via llama-server as OpenAI-compatible on port 8081 continuously.
#
#   - autoregressive dense 24B → runs on llama-server (single backend prioritized for consistency)
#   - GGUF: bartowski Mistral-Small-24B-Instruct-2501 Q4_K_M (arch=llama)
#   - ctx: 65536 (64k, long textbook window; limited by RAM availability)
#
# Execution (systemd recommended):
#   ExecStart=/usr/bin/env bash llama_serve_mistral.sh
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# Load base and model environments (MODEL_SLUG should be set by the caller)
load_base_env
load_model_env "$MODEL_SLUG"

LLAMA_SERVER="${LLAMA_SERVER:-${HOME}/llama.cpp/llama-server}"
# Resolve GGUF path using the helper function from lib.sh
GGUF="$(model_gguf_path)"
PORT="${MISTRAL_PORT:-8081}"
CTX="${MISTRAL_CTX:-65536}"
THREADS="${MISTRAL_THREADS:-8}"
ALIAS="${MISTRAL_ALIAS:-mistral-large}"

[[ -x "$LLAMA_SERVER" ]] || { echo "[!!] $LLAMA_SERVER missing" >&2; exit 2; }
[[ -f "$GGUF" ]] || { echo "[!!] GGUF missing: $GGUF" >&2; exit 2; }

echo "==> llama-server: $ALIAS / $GGUF ctx=$CTX port=$PORT" >&2
# Tuning parameters (already set via environment)
# THREADS defaults to 8, KV_CACHE defaults to "q8_0" for best throughput on 9700X
exec "$LLAMA_SERVER" \
  -m "$GGUF" \
  --alias "$ALIAS" \
  --host "0.0.0.0" \
  --port "$PORT" \
  --ctx-size "$CTX" \
  -t "$THREADS" \
  --jinja
