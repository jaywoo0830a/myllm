#!/usr/bin/env bash
# ============================================================
# 02_download_model.sh
#   HuggingFace 에서 GGUF 모델을 내려받는다. (HF 토큰 인증 + 이어받기 + 병렬 분할)
#
# HF 토큰으로 속도/인증 개선:
#   - 토큰은 순서대로 찾는다:
#       1) env 파일의 HF_TOKEN
#       2) server/config/hf_token  (plain text 한 줄, gitignore 됨)
#       3) ~/.cache/huggingface/token (huggingface-cli login 산출물)
#   - 토큰이 있으면 Authorization 헤더를 붙여 인증 경로/대역폭 우선 처리.
#
# 속도:
#   - 기본: curl 단일 스트림 + --continue-at(이어받기).
#   - HF_DL_THREADS>1 이고 aria2c 가 설치된 경우: 멀티커넥션 분할다운로드(빠름).
#     (설치: sudo apt install aria2)
#
# 사용법:
#   source ../config/env
#   bash 02_download_model.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SERVER_DIR/config/env"

# --- env 로드 ---
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "[!!] 환경설정 없음: server/config/env.example -> env 복사 후 편집하세요." >&2
  exit 1
fi

MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
HF_REPO="${HF_REPO:?env 에 HF_REPO 필요}"
MODEL_FILE="${MODEL_FILE:?env 에 MODEL_FILE 필요}"
mkdir -p "$MODEL_DIR"
OUT_PATH="$MODEL_DIR/$MODEL_FILE"

# --- HF 토큰 해석 (빈 환경변수값, 파일 공백 모두 처리) ---
resolve_token() {
  # 1) env 의 HF_TOKEN (빈 문자열이면 건너뜀)
  if [[ -n "${HF_TOKEN:-}" ]]; then echo "$HF_TOKEN"; return; fi
  # 2) server/config/hf_token 파일
  local tf="$SERVER_DIR/config/hf_token"
  if [[ -f "$tf" ]]; then tr -d ' \t\r\n' < "$tf"; return; fi
  # 3) huggingface-hub 기본 토큰 경로
  local hub="$HOME/.cache/huggingface/token"
  if [[ -f "$hub" ]]; then tr -d ' \t\r\n' < "$hub"; return; fi
  echo ""
}
HF_TOKEN="$(resolve_token)"

AUTH_HEADER=()
if [[ -n "$HF_TOKEN" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer $HF_TOKEN")
  echo "==> HF 토큰 사용 (인증 다운로드)"
else
  echo "==> HF 토큰 없음 (비인증). 속도 개선을 원하면 server/config/hf_token 에 Read 토큰을 넣으세요."
fi

URL="https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}"
echo "==> 대상: $URL"
echo "    저장: $OUT_PATH"

# --- 이미 존재하면 스킵 ---
if [[ -f "$OUT_PATH" ]]; then
  echo "==> 이미 존재: $OUT_PATH  (스킵, 재다운로드는 파일 삭제 후 재실행)"
  du -h "$OUT_PATH" | cut -f1
  exit 0
fi

# --- 다운로더: aria2c(병렬 분할) 또는 curl(단일+이어받기) ---
USE_ARIA=""
if command -v aria2c >/dev/null 2>&1 && [[ "${HF_DL_THREADS:-}" =~ ^[2-9]$ ]]; then
  USE_ARIA="yes"
fi

if [[ -n "$USE_ARIA" ]]; then
  echo "==> aria2c 멀티커넥션 분할 다운로드 (x=${HF_DL_THREADS})"
  aria2c \
    -x "$HF_DL_THREADS" -s "$HF_DL_THREADS" -k 4M \
    --file-allocation=none \
    --continue=true \
    --max-tries=5 --retry-wait=3 --timeout=60 --connect-timeout=30 \
    --console-log-level=warn \
    --summary-interval=5 \
    --header="Authorization: Bearer $HF_TOKEN" \
    -d "$MODEL_DIR" -o "$MODEL_FILE" "$URL"
else
  echo "==> curl 단일 스트림 + 이어받기"
  # -L: 302 follow(cdn-lfs), --continue-at -: 중단 시 이어받기, --retry: 일시오류 재시도
  curl -L --fail --progress-bar \
    --continue-at - \
    --retry 5 --retry-delay 3 --retry-all-errors \
    "${AUTH_HEADER[@]}" \
    "$URL" -o "$OUT_PATH"
fi

# --- 결과 점검 ---
echo ""
if [[ -f "$OUT_PATH" ]]; then
  echo "==> 다운로드 완료: $OUT_PATH"
  echo "    크기: $(du -h "$OUT_PATH" | cut -f1)"
else
  echo "[!!] 다운로드 실패" >&2
  exit 1
fi
