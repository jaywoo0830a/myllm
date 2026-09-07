#!/usr/bin/env bash
# ============================================================
# run_one.sh <slug>
#   지정 모델 프로파일로 llama-server 를 포그라운드 실행 (테스트/수동).
#   Ctrl+C 로 종료. systemd 상시화는 install_models.sh 참고.
#
# slug 예: deepseek-r1-32b
#
# 사용법:
#   bash run_one.sh deepseek-r1-32b
# ============================================================
set -euo pipefail

SLUG="${1:?사용법: bash run_one.sh <slug> (예: deepseek-r1-32b)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_base_env
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
load_model_env "$SLUG"     # MODEL_NAME/ALIAS/HF_REPO/MODEL_FILE/LLAMA_PORT/CTX_SIZE/THREADS...

BIN="$LLAMA_CPP_DIR/llama-server"
MODEL="$(model_gguf_path)"

[[ -x "$BIN" ]] || { echo "[!!] llama-server 없음: $BIN   (01_setup_llamacpp.sh 실행)" >&2; exit 1; }
if [[ ! -f "$MODEL" ]]; then
  echo "[!!] 모델 없음: $MODEL" >&2
  echo "    →  download.sh $SLUG  실행 필요" >&2
  exit 1
fi

THREAD_FLAGS=()
if [[ "${THREADS:-0}" != "0" ]]; then THREAD_FLAGS=(-t "$THREADS"); fi

THINK_ARGS=()
# NO_THINK=1 이면 reasoning(<think>) 억제: --reasoning off
#  (참고: 옛 `--no-think` 는 최신 llama.cpp 에서 invalid arg. --reasoning [on|off|auto] 사용)
if [[ "${NO_THINK:-0}" == "1" ]]; then THINK_ARGS+=(--reasoning off); fi

# KV 캐시 양자화 (OPT: 메모리 대역폭 절약으로 디코드 t/s 개선).
#   프로파일 KV_CACHE 예: "q8_0"
#   안전 처리: 이 llama.cpp 빌드가 어떤 cache 옵션을 지원하는지 --help 로 탐지하고,
#   지원되는 경우에만 추가한다. 미지원이면 조용히 스킵(시작 실패 방지).
CACHE_ARGS=()
if [[ -n "${KV_CACHE:-}" ]]; then
  # 지원 문법 탐지: 우선순위 1) --cache-type k:..,v:..  2) --no-kv (구식)  3) 없음
  _help="$("$BIN" --help 2>&1)"
  if grep -q -- "--cache-type" <<<"$_help"; then
    case "$KV_CACHE" in
      *:*) CACHE_ARG="--cache-type ${KV_CACHE}" ;;
      *)   CACHE_ARG="--cache-type k:${KV_CACHE},v:${KV_CACHE}" ;;
    esac
    CACHE_ARGS=($CACHE_ARG)
    echo "==> KV 캐시: $KV_CACHE (--cache-type 지원 확인)"
  else
    echo "==> [warn] 이 llama.cpp 는 --cache-type 미지원 → KV_CACHE($KV_CACHE) 무시하고 기본(f16)으로 시작" >&2
  fi
fi

print_model_summary
echo "==> 시작 (Ctrl+C 종료)"
echo ""

exec "$BIN" \
  -m "$MODEL" \
  --alias "$ALIAS" \
  --host "${LLAMA_HOST:-0.0.0.0}" \
  --port "$LLAMA_PORT" \
  --ctx-size "$CTX_SIZE" \
  --batch-size "$BATCH" \
  --ubatch-size "$UBATCH" \
  --parallel "$PARALLEL" \
  --jinja \
  "${CACHE_ARGS[@]}" \
  "${THINK_ARGS[@]}" \
  "${THREAD_FLAGS[@]}"


