#!/usr/bin/env bash
# run_local.sh — 호스트(9700X 서버)에서 API 를 직접 실행하는 편의 스크립트.
#
#   배경: up/down/start_heavy 는 실제 llama-server 를 제어해야 하므로,
#         컨테이너가 아니라 "호스트 프로세스"에서 API 를 띄워야 동작한다.
#
#   Python 선택 (자동):
#     저장소에 .venv 이 있으면 → .venv/bin/python 을 쓴다 (권장, PEP668 대응)
#     없으면 시스템 python3 로 폴백
#
#   사용:
#     bash scripts/api/run_local.sh [port=18080]          # 개발(reload 켬)
#     PYTHON_RELOAD=0 bash scripts/api/run_local.sh 18080 # 프로덕션(reload 끔, systemd)
#
#   PYTHONPATH 를 저장소 루으로 잡아 scripts.api 을 import 한다.
#   EXTERNAL_TOKEN 이 이미 export 되어 있으면 그대로 사용한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PORT="${1:-18080}"
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"

# ── Python 인터프리터 선택: venv 우선, 시스템 폴백 ───────────────
PY="python3"
if [[ -x "${REPO}/.venv/bin/python" ]]; then
    PY="${REPO}/.venv/bin/python"
    echo "[API] python = venv (${PY})"
else
    echo "[API] python = system (${PY}) — 저장소에 .venv 없음. 설치: python3 -m venv .venv"
fi

RELOAD=("--reload")
[[ "${PYTHON_RELOAD:-1}" == "0" ]] && RELOAD=()

echo "[API] uvicorn (host) — port=$PORT, repo=$REPO  reload=${RELOAD[*]:-off}"
exec "$PY" -m uvicorn scripts.api.app:app \
  --host 0.0.0.0 \
  --port "$PORT" \
  "${RELOAD[@]}"