#!/usr/bin/env bash
# ============================================================
# llama_serve_mistral.sh
#   Mistral-Small-24B-Instruct-2501 (LLAMA arch GGUF, autoregressive) 를
#   llama-server 로 OpenAI 호환 8081 상시 서빙.
#
#   - autoregressive dense 24B → llama-server 로 구동 (일관성 우선 단일 백엔드)
#   - GGUF: bartowski Mistral-Small-24B-Instruct-2501 Q4_K_M (arch=llama)
#   - ctx: 65536 (64k, 긴 교재용 창; RAM 여유까지만)
#
# 실행(systemd 사용 권장):
#   ExecStart=/usr/bin/env bash llama_serve_mistral.sh
# ============================================================
set -euo pipefail

LLAMA_SERVER="${LLAMA_SERVER:-${HOME}/llama.cpp/llama-server}"
GGUF="${MISTRAL_GGUF:-${HOME}/models/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf}"
PORT="${MISTRAL_PORT:-8081}"
CTX="${MISTRAL_CTX:-65536}"
THREADS="${MISTRAL_THREADS:-8}"
ALIAS="${MISTRAL_ALIAS:-mistral-large}"

[[ -x "$LLAMA_SERVER" ]] || { echo "[!!] $LLAMA_SERVER 없음" >&2; exit 2; }
[[ -f "$GGUF" ]] || { echo "[!!] GGUF 없음: $GGUF" >&2; exit 2; }

echo "==> llama-server: $ALIAS / $GGUF ctx=$CTX port=$PORT" >&2
exec "$LLAMA_SERVER" \
  -m "$GGUF" \
  --alias "$ALIAS" \
  --host "0.0.0.0" \
  --port "$PORT" \
  --ctx-size "$CTX" \
  -t "$THREADS" \
  --jinja
