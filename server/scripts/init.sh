#!/usr/bin/env bash
# ============================================================
# init.sh — Initialize Mistral server environment
#   Creates necessary directories and ensures the model file exists.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

# Ensure the output directory exists
GEN_ROOT="${SERVER_CONFIG_DIR}/../output"
mkdir -p "$GEN_ROOT"

# Load base and model environments (replace MODEL_NAME with your model slug)
MODEL_SLUG="${1:-mistral-large}"
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null
# Tuning parameters for optimal performance on AMD 9700X + DDR5 64 GB
export THREADS=8               # one thread per physical core
export KV_CACHE="q8_0"         # KV‑Cache quantisation for a small speed boost

echo "Initialization complete for model slug: $MODEL_SLUG"
echo "Output directory: $GEN_ROOT"