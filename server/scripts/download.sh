#!/usr/bin/env bash
# ============================================================
# download.sh <slug>
#   지정 모델의 GGUF 를 HF 에서 다운로드 (토큰 인증·이어받기·선택 병렬).
#
# slug 예: deepseek-r1-32b
#
# 사용법:
#   bash download.sh deepseek-r1-32b
# ============================================================
set -euo pipefail

SLUG="${1:?사용법: bash download.sh <slug> (예: deepseek-r1-32b)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_base_env
MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
load_model_env "$SLUG"

mkdir -p "$MODEL_DIR"
OUT_PATH="$(model_gguf_path)"

# --- HF 토큰 해석 ---
HF_TOKEN="$(resolve_hf_token)"
AUTH_HEADER=()
if [[ -n "$HF_TOKEN" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer $HF_TOKEN")
  echo "==> HF 토큰 사용 (인증 다운로드)"
else
  echo "==> HF 토큰 없음. 속도 개선 원하면 06_set_hf_token.sh 실행."
fi

URL="https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}"
echo "==> [${MODEL_NAME}] 대상: $URL"
echo "            저장: $OUT_PATH"

if [[ -f "$OUT_PATH" ]]; then
  echo "==> 이미 존재 (스킵): $OUT_PATH"
  du -h "$OUT_PATH" | cut -f1
  exit 0
fi

USE_ARIA=""
if command -v aria2c >/dev/null 2>&1 && [[ "${HF_DL_THREADS:-}" =~ ^[2-9]$ ]]; then
  USE_ARIA="yes"
fi

if [[ -n "$USE_ARIA" ]]; then
  echo "==> aria2c 분할 (x=${HF_DL_THREADS})"
  aria2c -x "$HF_DL_THREADS" -s "$HF_DL_THREADS" -k 4M \
    --file-allocation=none --continue=true \
    --max-tries=5 --retry-wait=3 --timeout=60 --connect-timeout=30 \
    --console-log-level=warn --summary-interval=5 \
    --header="Authorization: Bearer $HF_TOKEN" \
    -d "$MODEL_DIR" -o "$MODEL_FILE" "$URL"
else
  echo "==> curl 단일 + 이어받기"
  curl -L --fail --progress-bar --continue-at - \
    --retry 5 --retry-delay 3 --retry-all-errors \
    "${AUTH_HEADER[@]}" "$URL" -o "$OUT_PATH"
fi

echo ""
if [[ -f "$OUT_PATH" ]]; then
  echo "==> 완료: $OUT_PATH  ($(du -h "$OUT_PATH" | cut -f1))"
else
  echo "[!!] 실패" >&2; exit 1
fi
