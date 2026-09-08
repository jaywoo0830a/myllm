#!/usr/bin/env bash
# ============================================================
# llama_serve_generic.sh
#   Generic wrapper for llama‑server that works with any model defined in
#   `server/config/models/<slug>.env`. It reads the environment variables
#   from `load_model_env` (LLAMA_PORT, CTX_SIZE, THREADS, ALIAS, etc.) and
#   starts `llama‑server` with the appropriate arguments.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# Load base and model environments (MODEL_SLUG should be set by the caller)
load_base_env
load_model_env "${MODEL_SLUG}"

LLAMA_SERVER="${LLAMA_SERVER:-${HOME}/llama.cpp/llama-server}"
# Resolve GGUF path using the helper function from lib.sh
GGUF="$(model_gguf_path)"
# Use the generic variable names; fallback to defaults if not set
PORT="${LLAMA_PORT:-8080}"
CTX="${CTX_SIZE:-16384}"
THREADS="${THREADS:-8}"
ALIAS="${ALIAS:-${MODEL_NAME}}"

[[ -x "${LLAMA_SERVER}" ]] || { echo "[!!] $LLAMA_SERVER missing" >&2; exit 2; }
[[ -f "${GGUF}" ]] || { echo "[!!] GGUF missing: ${GGUF}" >&2; exit 2; }

echo "==> llama-server: ${ALIAS} / ${GGUF} ctx=${CTX} port=${PORT}" >&2
# Tuning parameters (already set via environment)
export OMP_NUM_THREADS=${THREADS}
export KMP_AFFINITY=granularity=fine,compact,1,0
exec "${LLAMA_SERVER}" \
  -m "${GGUF}" \
  --alias "${ALIAS}" \
  --host "0.0.0.0" \
  --port "${PORT}" \
  --ctx-size "${CTX}" \
  -t "${THREADS}"