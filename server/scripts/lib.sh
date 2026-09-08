#!/usr/bin/env bash
# ============================================================
# lib.sh — common helper functions (source to use)
#   Load order: config/env (base) -> config/models/<slug>.env (model)
#   Usage (at top of script):
#     SCRIPT_DIR=... (script location)
#     # shellcheck disable=SC1091
#     source "$SCRIPT_DIR/lib.sh"
#     load_base_env
#     load_model_env "${MODEL_NAME:?Usage: MODEL_NAME=... or argument}"
# ============================================================

# lib.sh determine its own location path
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_DIR="${_LIB_DIR}/../config"
export SERVER_CONFIG_DIR

# Ensure the run directory exists for PID and log files
RUN_DIR="${_LIB_DIR}/../run"
mkdir -p "$RUN_DIR"

# load_base_env: load config/env (if missing, guide to copy .example and defaults are usable)
load_base_env() {
  local ENV_FILE="$SERVER_CONFIG_DIR/env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  else
    echo "[warn] $ENV_FILE not found. See server/config/env.example to create it." >&2
    LLAMA_HOST="${LLAMA_HOST:-0.0.0.0}"
    MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
    LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
  fi
}

# load_model_env <slug>: load config/models/<slug>.env (guide if missing)
#   On success, MODEL_NAME, ALIAS, HF_REPO, MODEL_FILE, LLAMA_PORT, etc. are populated.
load_model_env() {
  local slug="${1:?load_model_env: slug required}"
  local f="$SERVER_CONFIG_DIR/models/${slug}.env"
  if [[ ! -f "$f" ]]; then
    echo "[!!] Model profile not found: $f" >&2
    echo "    Note: cp server/config/models/${slug}.env.example $f" >&2
    exit 1
  fi
# shellcheck disable=SC1090
# Source the environment file while stripping possible Windows CR characters
source <(tr -d '\r' < "$f")
  # Required validation
  : "${MODEL_NAME:?missing: MODEL_NAME}"
  : "${ALIAS:?missing: ALIAS}"
  : "${HF_REPO:?missing: HF_REPO}"
  : "${MODEL_FILE:?missing: MODEL_FILE}"
  : "${LLAMA_PORT:?missing: LLAMA_PORT}"
  # Default values
  CTX_SIZE="${CTX_SIZE:-16384}"
  NO_THINK="${NO_THINK:-0}"
  THREADS="${THREADS:-0}"
  PARALLEL="${PARALLEL:-1}"
  BATCH="${BATCH:-512}"
  UBATCH="${UBATCH:-512}"
  KV_CACHE="${KV_CACHE:-}"
}

# resolve_hf_token: HF_TOKEN / hf_token file / ~/.cache/huggingface/token order
resolve_hf_token() {
  if [[ -n "${HF_TOKEN:-}" ]]; then echo "$HF_TOKEN"; return; fi
  local tf="$SERVER_CONFIG_DIR/hf_token"
  if [[ -f "$tf" ]]; then tr -d ' \t\r\n' < "$tf"; return; fi
  local hub="$HOME/.cache/huggingface/token"
  if [[ -f "$hub" ]]; then tr -d ' \t\r\n' < "$hub"; return; fi
  echo ""
}

# model_gguf_path: absolute path of the GGUF to be downloaded
model_gguf_path() {
  echo "${MODEL_DIR}/${MODEL_FILE}"
}

# print_model_summary
print_model_summary() {
  echo "Model: ${MODEL_NAME}  (alias=${ALIAS})"
  echo "  repo : ${HF_REPO} :: ${MODEL_FILE}"
  echo "  port : ${LLAMA_HOST}:${LLAMA_PORT}  ctx=${CTX_SIZE}"
  echo "  path : $(model_gguf_path)"
}