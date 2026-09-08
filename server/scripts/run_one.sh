#!/usr/bin/env bash
# ============================================================
# run_one.sh <slug>
#   지정 모델 프로파일로 llama-server 를 포그라운드 실행 (테스트/수동).
#   Ctrl+C 로 종료. systemd 상시화는 install_models.sh 참고.
#
# slug 예: deepseek-r1-14b
#
# 사용법:
#   bash run_one.sh deepseek-r1-14b
# ============================================================
set -euo pipefail

SLUG="${1:?사용법: bash run_one.sh <slug> (예: deepseek-r1-14b)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_base_env
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
load_model_env "$SLUG"     # MODEL_NAME/ALIAS/HF_REPO/MODEL_FILE/LLAMA_PORT/CTX_SIZE/THREADS...

BIN="$LLAMA_CPP_DIR/llama-server"
MODEL="$(model_gguf_path)"

[[ -x "$BIN" ]] || { echo "[!!] llama-server 없음: $BIN   (setup_llamacpp.sh 실행)" >&2; exit 1; }
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
#   이 llama.cpp 는 개별 플래그 --cache-type-k / --cache-type-v 를 쓴다 (-ctk/-ctv).
#   단일 --cache-type 문법이 아님에 주의. 지원 여부를 --help 로 탐지해 추가.
#   미지원이면 경고 후 스킵 (시작 실패 방지).
CACHE_ARGS=()
if [[ -n "${KV_CACHE:-}" ]]; then
  _help="$("$BIN" --help 2>&1)"
  if grep -q -- "--cache-type-k" <<<"$_help"; then
    # 값이 "k:..","v:.."콤마 형태면 분리, 아니면 K/V 양쪽에 동일 적용
    case "$KV_CACHE" in
      *:*)
        # 예: "k:q4_0,v:q8_0" 지원
        KTYPE="$(cut -d, -f1 <<<"$KV_CACHE" | cut -d: -f2)"
        VTYPE="$(cut -d, -f2 <<<"$KV_CACHE" | cut -d: -f2)"
        [[ -n "$KTYPE" ]] && CACHE_ARGS+=(--cache-type-k "$KTYPE")
        [[ -n "$VTYPE" ]] && CACHE_ARGS+=(--cache-type-v "$VTYPE")
        ;;
      *)
        CACHE_ARGS=(--cache-type-k "$KV_CACHE" --cache-type-v "$KV_CACHE")
        ;;
    esac
    echo "==> KV 캐시: K=${KV_CACHE%%:*} V=${KV_CACHE##*:}"
    echo "    args: ${CACHE_ARGS[*]}"
  else
    echo "==> [warn] 이 llama.cpp 는 --cache-type-k 미지원 → KV_CACHE($KV_CACHE) 무시, 기본(f16) 시작" >&2
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


