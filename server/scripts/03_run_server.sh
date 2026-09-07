#!/usr/bin/env bash
# ============================================================
# 03_run_server.sh
#   llama-server 를 포그라운드로 실행 (테스트/수동 운영용).
#   `Ctrl+C` 로 종료.
#
#   systemd 등으로 상시 실행하려면 아래를 대신 사용:
#     bash 05_install_systemd.sh
#
# 사용법:
#   source ../config/env
#   bash 03_run_server.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/config/env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "[!!] 환경설정 없음: server/config/env.example -> env 복사 후 편집하세요." >&2
  exit 1
fi

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
BIN="$LLAMA_CPP_DIR/llama-server"
MODEL="${MODEL_DIR:-${HOME}/models}/${MODEL_FILE:?env 에 MODEL_FILE 필요}"

[[ -x "$BIN" ]] || { echo "[!!] llama-server 없음. 01_setup_llamacpp.sh 먼저 실행." >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "[!!] 모델 없음: $MODEL  (02_download_model.sh 실행)" >&2; exit 1; }

# CPU 스레드
if [[ "${THREADS:-0}" != "0" ]]; then
  THREAD_FLAGS=(-t "$THREADS")
else
  THREAD_FLAGS=()
fi

# <think> off 플래그 조립
THINK_ARGS=()
if [[ "${NO_THINK:-1}" == "1" ]]; then
  # 최신 llama.cpp: --no-think (구버전은 미지원 -> 에러 시 아래 -D 플래그 확인)
  THINK_ARGS+=(--no-think)
fi

echo "==> 모델: $MODEL"
echo "==> 바인딩: ${LLAMA_HOST}:${LLAMA_PORT}, ctx=${CTX_SIZE:-16384}"
echo ""

exec "$BIN" \
  -m "$MODEL" \
  --host "${LLAMA_HOST:-0.0.0.0}" \
  --port "${LLAMA_PORT:-8080}" \
  --ctx-size "${CTX_SIZE:-16384}" \
  --batch-size "${BATCH:-512}" \
  --ubatch-size "${UBATCH:-512}" \
  --parallel "${PARALLEL:-1}" \
  --jinja \
  "${THINK_ARGS[@]}" \
  "${THREAD_FLAGS[@]}"
