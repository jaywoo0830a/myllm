#!/usr/bin/env bash
# ============================================================
# init.sh — Initialize the server environment
#   Creates config from examples, dirs, then loads base+model env.
#   Usage: bash init.sh [model_slug=parser]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

# -------------------------------------------------
# 0) Ensure configuration files exist (env & model envs)
# -------------------------------------------------
CONFIG_DIR="${SCRIPT_DIR}/../config"
if [[ ! -f "${CONFIG_DIR}/env" ]]; then
    cp "${CONFIG_DIR}/env.example" "${CONFIG_DIR}/env"
    echo "Created ${CONFIG_DIR}/env from example"
fi
for example in "${CONFIG_DIR}/models/"*.env.example; do
    model=$(basename "$example" .env.example)
    target="${CONFIG_DIR}/models/${model}.env"
    if [[ ! -f "$target" ]]; then
        cp "$example" "$target"
        echo "Created $target from $example"
    fi
done

# -------------------------------------------------
# 1) Ensure the output directory exists
# -------------------------------------------------
GEN_ROOT="${SERVER_CONFIG_DIR}/../output"
mkdir -p "$GEN_ROOT"

# -------------------------------------------------
# 2) Ensure the run directory exists for PID and log files
# -------------------------------------------------
RUN_DIR="${SCRIPT_DIR}/../run"
mkdir -p "$RUN_DIR"

# -------------------------------------------------
# 3) Load base and model environments (default: parser)
# -------------------------------------------------
MODEL_SLUG="${1:-parser}"
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null
# Tuning parameters for optimal performance on AMD 9700X + DDR5 64GB
# (실제 반영은 llama_serve_generic.sh 가 명령줄 플래그로 수행)
export THREADS="${THREADS:-8}"
export KV_CACHE="${KV_CACHE:-q8_0}"

echo "[OK] Initialization complete for model slug: $MODEL_SLUG"
echo "     Output directory : $GEN_ROOT"
echo "     Run directory    : $RUN_DIR"
