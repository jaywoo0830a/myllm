#!/usr/bin/env bash
# ============================================================
# diffuse_serve.sh <model>  — diffuse-cpp(diffusion: llada/dream) 를
#                             OpenAI 호환 서버로 상시 구동(start 대상).
#
#   model -> gguf / tokenizer / port / mask 매핑:
#     llada : llada-8b-q4km.gguf , ~/models/llada-tokenizer , 8081 , mask 126336
#     dream : dream-7b-q4km.gguf , ~/models/dream-tokenizer , 8082 , mask 151666
#
#   (DIFFUSE_PORT / DIFFUSE_SLUG 등으로 덮어쓸 수 있음)
#
# 실행: exec로 python diffuse_server.py 를 띄운다(systemd 가 관리).
# ============================================================
set -euo pipefail

MODEL="${1:-${DIFFUSE_MODEL:-llada}}"
VENV_PY="${DIFFUSE_PY:-${HOME}/venv-diffuse/bin/python}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/diffuse_server.py"
CPP_BIN="${DIFFUSE_CPP:-${HOME}/diffuse-cpp/diffuse-cli}"
M_DIR="${HOME}/models/diffuse"
TOK_DIR="${HOME}/models"

case "$MODEL" in
  llada|LLaDA|llada-8b|llada-8b-instruct)
    GGUF="$M_DIR/llada-8b-q4km.gguf"
    TOK="$TOK_DIR/llada-tokenizer"
    PORT="${DIFFUSE_PORT:-8081}"
    ;;
  dream|Dream|dream-7b)
    GGUF="$M_DIR/dream-7b-q4km.gguf"
    TOK="$TOK_DIR/dream-tokenizer"
    PORT="${DIFFUSE_PORT:-8082}"
    ;;
  *)
    echo "[!!] 알 수 없는 diffusion 모델: $MODEL (llada|dream)" >&2
    exit 2
    ;;
esac

[[ -f "$GGUF" ]] || { echo "[!!] GGUF 없음: $GGUF" >&2; exit 2; }
[[ -d "$TOK" ]] || { echo "[!!] 토크나이저 없음: $TOK" >&2; exit 2; }
[[ -x "$VENV_PY" ]] || { echo "[!!] venv python 없음: $VENV_PY" >&2; exit 2; }

export LD_LIBRARY_PATH="$HOME/diffuse-cpp/build:$HOME/diffuse-cpp/build/ggml/src${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
echo "==> diffuse_serve: model=$MODEL port=$PORT" >&2
exec "$VENV_PY" "$APP" \
  --gguf "$GGUF" --tokenizer "$TOK" --cpp-bin "$CPP_BIN" --port "$PORT"
