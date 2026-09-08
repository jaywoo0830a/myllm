#!/usr/bin/env bash
# ============================================================
# down_all.sh — Kill every running llama-server and clean up
#   Usage: bash scripts/down_all.sh
#
#   Stops ALL llama-server processes (parser/worker/coder/reasoner/
#   setter/judge/...), removes their pid files and logs under run/.
#   Safe to re-run; does not require slug names.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${SCRIPT_DIR}/../run"

echo "── 모든 llama-server 종료 시도 ──────────────────────"

# 1) 실행 중인 llama-server PID 수집 (있으면)
PIDS="$(pgrep -f llama-server 2>/dev/null || true)"

if [[ -n "$PIDS" ]]; then
  echo "감지된 PID: $(echo "$PIDS" | tr '\n' ' ')"
  # 우아한 종료(SIGTERM)
  echo "$PIDS" | xargs -r kill -TERM 2>/dev/null || true
  # 최대 10초 대기
  for _ in $(seq 1 10); do
    pgrep -f llama-server >/dev/null 2>&1 || break
    sleep 1
  done
  # 남아있으면 강제 종료(SIGKILL)
  REMAIN="$(pgrep -f llama-server 2>/dev/null || true)"
  if [[ -n "$REMAIN" ]]; then
    echo "⚠️  SIGTERM 후에도 남음 → SIGKILL: $(echo "$REMAIN" | tr '\n' ' ')"
    echo "$REMAIN" | xargs -r kill -KILL 2>/dev/null || true
  fi
else
  echo "실행 중인 llama-server 없음."
fi

# 2) run/ 잔재(pid/log) 정리
if [[ -d "$RUN_DIR" ]]; then
  find "$RUN_DIR" -maxdepth 1 \( -name '*.pid' -o -name '*.log' \) -delete 2>/dev/null \
    && echo "🧹 run/*.pid, run/*.log 정리 완료"
fi

# 3) 확인
LEFT="$(pgrep -af llama-server 2>/dev/null || true)"
if [[ -n "$LEFT" ]]; then
  echo "❌ 아직 남아있는 프로세스:"
  echo "$LEFT"
  exit 1
fi

echo "✅ 모든 llama-server가 내려갔습니다."
