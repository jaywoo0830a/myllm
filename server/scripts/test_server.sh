#!/usr/bin/env bash
# ============================================================
# test_server.sh
#   llama-server 가 떠 있는지 /v1 OpenAI 호환 스모크 테스트.
#   서버가 LOCAL(이 머신)이면 그대로, 원격이면 HOST/PORT 를 환변수로.
#
# 사용법:
#   # 로컬 기본값(127.0.0.1:8080) 사용
#   bash test_server.sh
#   # 원격 서버 지정
#   LLAMA_HOST=192.168.0.50 LLAMA_PORT=8080 bash test_server.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/config/env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  # env 없는 경우 기본값
  LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
  LLAMA_PORT="${LLAMA_PORT:-8080}"
fi

BASE="http://${LLAMA_HOST:-127.0.0.1}:${LLAMA_PORT}"
echo "==> 서버: $BASE"

# 1) 헬스
echo "--- GET $BASE/health ---"
curl -sS "$BASE/health" || { echo "연결 실패"; exit 1; }
echo ""

# 2) chat completion (간단 질문, no stream)
echo "--- POST $BASE/v1/chat/completions ---"
curl -sS "$BASE/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [
      {"role":"system","content":"You are a helpful assistant. Answer very briefly."},
      {"role":"user","content":"Reply with the single word: pong"}
    ],
    "max_tokens": 32,
    "temperature": 0
  }' | python3 -c "import sys,json;d=json.load(sys.stdin);print('ANSWER:', d['choices'][0]['message']['content'])" 2>/dev/null \
  || echo "(python 파싱 실패시 위 원문 JSON 을 확인)"

echo ""
echo "==> 스모크 테스트 완료."
