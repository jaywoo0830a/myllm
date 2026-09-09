#!/usr/bin/env bash
# run_local.sh — 호스트(9700X 서버)에서 API 를 직접 실행하는 편의 스크립트.
#
#   배경: up/down/start_heavy 는 실제 llama-server 를 제어해야 하므로,
#         컨테이너가 아니라 "호스트 프로세스"에서 API 를 띄워야 동작한다.
#   사용: bash scripts/api/run_local.sh [port=8000]
#
#   PYTHONPATH 를 저장소 루으로 잡아 scripts.api 을 import 한다.
#   EXTERNAL_TOKEN 이 이미 export 되어 있으면 그대로 사용한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PORT="${1:-8000}"
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"

echo "[API] uvicorn (host) — port=$PORT, repo=$REPO"
exec python3 -m uvicorn scripts.api.app:app \
  --host 0.0.0.0 \
  --port "$PORT" \
  --reload