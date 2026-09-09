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

# ---------------------------------------------------------------------------
# 성능 튜닝 플래그
#   (주의) --parallel 은 사용하지 않는다 — CPU(메모리 대역폭 결합)에선 병렬 요청이
#           총 처리량을 늘리지 못하고 레이턴시·메모리만 악화시킨다 (M1).
#   - --cache-type-k / --cache-type-v : KV 캐시 양자화 분리 플래그
#       (q8_0 → 14B 판사의 KV 할당 절반으로). 이 llama.cpp 빌드(build 10858+)는
#       예전의 통합 `--cache-type "k:...,v:..."` 플래그를 제거했으므로,
#       K/V 를 각각 별도 플래그로 넘겨야 한다.
#   - -b / -ub  : 배치 크기 (프리필 처리량, M2: 연산 결합 = 프리필 최대화)
# ---------------------------------------------------------------------------
BATCH="${BATCH:-512}"
UBATCH="${UBATCH:-512}"
KV_TYPE="${KV_CACHE}"   # q8_0(기본) / q4_0 / f16(비활성화) / 비우면 양자화 생략

# KV 캐시 양자화 인자 (KV_CACHE 가 비어 있으면 플래그 자체를 생략 → 기본 f16)
KV_ARGS=()
if [[ -n "${KV_TYPE}" ]]; then
  KV_ARGS+=(--cache-type-k "${KV_TYPE}" --cache-type-v "${KV_TYPE}")
fi

exec "${LLAMA_SERVER}" \
  -m "${GGUF}" \
  --alias "${ALIAS}" \
  --host "0.0.0.0" \
  --port "${PORT}" \
  --ctx-size "${CTX}" \
  -t "${THREADS}" \
  -b "${BATCH}" -ub "${UBATCH}" \
  "${KV_ARGS[@]}"