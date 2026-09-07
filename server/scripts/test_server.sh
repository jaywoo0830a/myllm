#!/usr/bin/env bash
# ============================================================
# test_server.sh [slug]
#   llama-server 가 떠 있는지 /v1 OpenAI 호환 스모크 테스트.
#
# 사용법:
#   # 첫 번째 인자로 slug 지정하면 해당 포트 자동 선택
#   bash test_server.sh deepseek-1.5b     # -> config/models 에서 포트 읽음
#   bash test_server.sh qwen3-14b
#   # 혹은 직접 주소 지정
#   LLAMA_HOST=192.168.0.50 LLAMA_PORT=8081 bash test_server.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [[ -n "${1:-}" ]]; then
  load_base_env
  load_model_env "$1" >/dev/null
  LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
elif [[ -f "$SERVER_CONFIG_DIR/env" ]]; then
  # shellcheck disable=SC1090
  source "$SERVER_CONFIG_DIR/env"
  LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
  LLAMA_PORT="${LLAMA_PORT:-8080}"
else
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
