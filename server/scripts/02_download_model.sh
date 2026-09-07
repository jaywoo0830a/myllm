#!/usr/bin/env bash
# ============================================================
# 02_download_model.sh
#   HuggingFace 에서 GGUF 모델을 내려받는다.
#   HF_REPO/MODEL_FILE 은 server/config/env(.example) 에서 지정.
#
# 사용법:
#   source ../config/env
#   bash 02_download_model.sh
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

MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
HF_REPO="${HF_REPO:?env 에 HF_REPO 필요}"
MODEL_FILE="${MODEL_FILE:?env 에 MODEL_FILE 필요}"

mkdir -p "$MODEL_DIR"
OUT_PATH="$MODEL_DIR/$MODEL_FILE"

# 1) 로컬에 이미 있으면 스킵
if [[ -f "$OUT_PATH" ]]; then
  echo "==> 이미 존재: $OUT_PATH  (스킵)"
else
  echo "==> 다운로드: hf.co/$HF_REPO/resolve/main/$MODEL_FILE"
  echo "    -> $OUT_PATH"
  # HF_LFS_ENDPOINT 기본 그대로. curl 로 메타+파일 내려받기(리다이렉트/302 자동 처리)
  curl -L --fail --progress-bar \
    "https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}" \
    -o "$OUT_PATH"
fi

# 2) 기본값 로컬 경로는 env 가 없어도 이 script 안에서 재사용 가능하게 기록용 echo
echo ""
echo "==> 모델 준비 완료: $OUT_PATH"
echo "    파일 크기: $(du -h "$OUT_PATH" | cut -f1)"
ls -la "$MODEL_DIR"
