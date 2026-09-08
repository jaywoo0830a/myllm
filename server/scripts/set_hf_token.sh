#!/usr/bin/env bash
# ============================================================
# set_hf_token.sh
#   HuggingFace Read 토큰을 server/config/hf_token 에 저장한다.
#   - hf_token 은 .gitignore 대상 -> git 에 커밋/푸시되지 않음 (비밀 보호)
#   - `read -s` 로 입력받아 터미널 히스토리/화면에 노출하지 않는다.
#
# 토큰 생성: https://huggingface.co/settings/tokens -> "Read" 권한
#
# 사용법:
#   bash set_hf_token.sh
#   # 입력 프롬프트에 토큰을 붙여넣고 Enter
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
TOKEN_FILE="$SERVER_DIR/config/hf_token"

if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
  echo "==> 이미 토큰이 설정돼 있습니다: $TOKEN_FILE"
  read -r -p "교체하려면 y, 유지하려면 그 외 키: " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "유지합니다."
    exit 0
  fi
fi

echo -n "HF Read 토큰 입력 (입력 내용은 표시되지 않음): "
read -r -s TOKEN
echo ""
if [[ -z "$TOKEN" ]]; then
  echo "[!!] 빈 입력. 취소." >&2
  exit 1
fi

mkdir -p "$SERVER_DIR/config"
# 개행 없이 한 줄로 저장 (권한을 소유자만 읽게)
umask 177
printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

echo "==> 저장 완료: $TOKEN_FILE (권한 600, git 무시됨)"
echo "    이제 bash download.sh <slug> 를 실행하면 인증 다운로드로 진행됩니다."
