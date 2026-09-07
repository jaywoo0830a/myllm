#!/usr/bin/env bash
# ============================================================
# run_all.sh
#   모든 활성 모델 프로파일(config/models/*.env)을 백그라운드로 띄운다.
#   - 테스트용(포그라운드 2개를 나란히)이므로 상시 운영은 install_models.sh( systemd) 권장.
#
# 사용법:
#   bash run_all.sh                 # 모든 .env 모델 시작
#   bash run_all.sh --download      # 시작 전에 GGUF 없으면 다운로드부터
#   bash run_all.sh --status        # 각 포트 health 확인만
#   bash run_all.sh --stop          # 시작했던 프로세스 종료
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

MODELS_DIR="$SERVER_CONFIG_DIR/models"
PID_DIR="${TMPDIR:-/tmp}/myllm-pids"
mkdir -p "$PID_DIR"

# 활성 slug 목록: config/models/*.env (실제 복사본만)
mapfile -t SLUGS < <(ls "$MODELS_DIR"/*.env 2>/dev/null | xargs -n1 basename | sed 's/\.env$//' | sort)

if [[ ${#SLUGS[@]} -eq 0 ]]; then
  echo "[!!] config/models/*.env 없음. .example 로 복사하세요.:" >&2
  ls "$MODELS_DIR"/*.env.example 2>/dev/null | xargs -n1 basename
  exit 1
fi

echo "활성 모델: ${SLUGS[*]}"

load_base_env
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
MODEL_DIR="${MODEL_DIR:-${HOME}/models}"

case "${1:-}" in
  --status)
    for s in "${SLUGS[@]}"; do
      load_model_env "$s" >/dev/null
      if curl -sf "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null; then
        echo "[ok] $s  -> http://${LLAMA_HOST}:${LLAMA_PORT}/health"
      else
        echo "[--] $s  (포트 ${LLAMA_PORT} 응답 없음)"
      fi
    done
    exit 0
    ;;
  --stop)
    for p in "$PID_DIR"/*.pid; do
      [[ -f "$p" ]] || continue
      kill "$(cat "$p")" 2>/dev/null && echo "stopped $(basename "$p")"
      rm -f "$p"
    done
    exit 0
    ;;
esac

WANT_DL=0
if [[ "${1:-}" == "--download" ]]; then WANT_DL=1; fi

for s in "${SLUGS[@]}"; do
  load_model_env "$s" >/dev/null
  BIN="$LLAMA_CPP_DIR/llama-server"
  MODEL="$(model_gguf_path)"
  [[ -x "$BIN" ]] || { echo "[!!] llama-server 없음. 01_setup_llamacpp.sh" >&2; exit 1; }
  if [[ ! -f "$MODEL" ]]; then
    if [[ $WANT_DL -eq 1 ]]; then
      echo "==> [${s}] 다운로드 시작"
      bash "$SCRIPT_DIR/download.sh" "$s"
    else
      echo "[!!] [${s}] 모델 없음: $MODEL  →  bash download.sh $s" >&2
      continue
    fi
  fi
  # 백그라운드로 실행 (로그는 서버의 journalctl 대신 파일로)
  LOG="$PID_DIR/${s}.log"
  (
    bash "$SCRIPT_DIR/run_one.sh" "$s"
  ) >"$LOG" 2>&1 &
  PID=$!
  echo "$PID" > "$PID_DIR/${s}.pid"
  echo "==> [${s}] 백그라운드 시작 pid=$PID  (로그: $LOG, 포트를 서버 로그에서 확인)"
  # 포트가 실제로 뜰 때까지 대기
  for i in $(seq 1 120); do
    sleep 1
    PORT="$( (load_model_env "$s" >/dev/null; echo "$LLAMA_PORT") )"
    if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      echo "    [${s}] READY http://127.0.0.1:${PORT}"
      break
    fi
    # 프로세스가 죽었으면 로그 보여주고 중단
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "    [${s}] 비정상 종료. 로그:"; tail -n 40 "$LOG"; break
    fi
  done
done

echo ""
echo "==> 백그라운드 프로세스 확인:"
for s in "${SLUGS[@]}"; do
  p="$PID_DIR/${s}.pid"; [[ -f "$p" ]] && echo "  $s pid=$(cat "$p")"
done
echo "  현재 세션 로그: $PID_DIR"
echo "  (systemd 로 상시화는: bash install_models.sh)"
