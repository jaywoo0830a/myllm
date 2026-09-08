#!/usr/bin/env bash
# ============================================================
# download.sh — Download a GGUF model file from Hugging Face
#   Usage: download.sh <model_slug>
#   The script respects HF_TOKEN if set, otherwise attempts anonymous download.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

# Load base and model environments
MODEL_SLUG="${1:-mistral-large}"
load_base_env
load_model_env "$MODEL_SLUG" >/dev/null

# Resolve target path for the GGUF file
TARGET_PATH="$(model_gguf_path)"
# Ensure target directory exists
mkdir -p "$(dirname "$TARGET_PATH")"

# If the file already exists, skip download
if [[ -f "$TARGET_PATH" ]]; then
  echo "Model already present at $TARGET_PATH"
  exit 0
fi

# Build the download URL using the HF_REPO variable from the model env
# Example: https://huggingface.co/unsloth/Mistral-Small-24B-Instruct-2501-GGUF/resolve/main/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf
DOWNLOAD_URL="https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}"

echo "Downloading $MODEL_FILE from $HF_REPO ..."
# Choose downloader: aria2c > curl > error
if command -v aria2c >/dev/null 2>&1; then
  # Parallel download with aria2c – number of connections can be tuned via HF_DL_THREADS (default 8)
  PARALLEL="${HF_DL_THREADS:-8}"
  HF_TOKEN="$(resolve_hf_token)"
  if [[ -n "$HF_TOKEN" ]]; then
    aria2c --header="Authorization: Bearer $HF_TOKEN" -x "$PARALLEL" -s "$PARALLEL" -k 1M -c "$DOWNLOAD_URL" -d "$(dirname "$TARGET_PATH")" -o "$(basename "$TARGET_PATH")"
  else
    aria2c -x "$PARALLEL" -s "$PARALLEL" -k 1M -c "$DOWNLOAD_URL" -d "$(dirname "$TARGET_PATH")" -o "$(basename "$TARGET_PATH")"
  fi
elif command -v curl >/dev/null 2>&1; then
  # Fallback to curl – use resume support (-C -) and optional token header
  HF_TOKEN="$(resolve_hf_token)"
  if [[ -n "$HF_TOKEN" ]]; then
    curl -L -H "Authorization: Bearer $HF_TOKEN" -C - "$DOWNLOAD_URL" -o "$TARGET_PATH"
  else
    curl -L -C - "$DOWNLOAD_URL" -o "$TARGET_PATH"
  fi
else
  echo "❌ Neither aria2c nor curl is installed. Please install one of them to download models." >&2
  exit 1
fi

echo "Download complete: $TARGET_PATH"