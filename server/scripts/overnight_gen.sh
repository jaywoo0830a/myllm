#!/usr/bin/env bash
# ============================================================
# overnight_gen.sh  —  장문(교재류) 생성을 "밤새" 백그라운드 실행
#
#   서버의 llama-server(/v1 OpenAI 호환)를 호출해 큰 응답을 파일로 저장.
#   - nohup + 백그라운드 → SSH 로그아웃/세션 종료에도 계속 실행
#   - reasoning(<think>)은 llama.cpp 가 reasoning_content 로 분리 → content 만 저장
#     (--keep-reasoning 시 reasoning 도 별도 파일로 저장)
#   - 프롬프트가 길 수 있으므로 지시는 파일(promptfile)로 준다.
#
# 사용법:
#   # 시작 (백그라운드, job 에 대한 pid/로그/상태)
#   bash overnight_gen.sh start <slug> <promptfile> [-s <systemfile>] [--keep-reasoning]
#
#   # 상태/로그
#   bash overnight_gen.sh status            # 최근 job 목록
#   bash overnight_gen.sh status <jobdir>
#
# 예시:
#   cat > /tmp/mybook_prompt.md <<'EOF'
#   나는 고등학생용 물리 교재를 쓰고 있어. 아래 개요로 30쪽 분량의 본문을
#   챕터 단위로 순서대로 이어서 생성해 줘...
#   EOF
#   bash overnight_gen.sh start deepseek-r1-14b /tmp/mybook_prompt.md
#
#   # 자고 일어나서:
#   bash overnight_gen.sh status
#   # 완료되면 <jobdir>/content.md 에 최종 결과.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

GEN_ROOT="$SERVER_DIR/output"
mkdir -p "$GEN_ROOT"

CMD="${1:-help}"
case "$CMD" in
  start)
    SLUG="${2:?사용법: start <slug> <promptfile>}"
    PROMPT_FILE="${3:?promptfile 필요 (긴 지시 텍스트 파일)}"
    shift 3 || true
    SYS_FILE=""
    KEEP_REASONING=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -s) SYS_FILE="$2"; shift 2;;
        --keep-reasoning) KEEP_REASONING=1; shift;;
        *) echo "[!!] 알 수 없는 인자: $1" >&2; exit 1;;
      esac
    done
    [[ -f "$PROMPT_FILE" ]] || { echo "[!!] promptfile 없음: $PROMPT_FILE" >&2; exit 1; }
    [[ -z "$SYS_FILE" || -f "$SYS_FILE" ]] || { echo "[!!] systemfile 없음: $SYS_FILE" >&2; exit 1; }

    # slug 의 포트/엔드포인트 결정
    load_base_env
    load_model_env "$SLUG" >/dev/null
    ENDPOINT="http://127.0.0.1:${LLAMA_PORT}/v1/chat/completions"
    echo "==> 스모크: $ENDPOINT"
    curl -sf --max-time 5 "$ENDPOINT" >/dev/null 2>&1 || {
      echo "호출 전: /v1/models 로 서버 생존 확인"
      curl -sf --max-time 5 "http://127.0.0.1:${LLAMA_PORT}/v1/models" >/dev/null || {
        echo "[!!] 서버가 ${LLAMA_PORT} 포트에 없음. systemctl start myllm-llama@${SLUG}" >&2; exit 1; }
    }

    TS="$(date +%Y%m%d-%H%M%S)"
    JOBDIR="$GEN_ROOT/${SLUG}-${TS}"
    mkdir -p "$JOBDIR"
    export LLAMA_SLUG="$SLUG" LLAMA_EP="$ENDPOINT" LLAMA_JOB="$JOBDIR" \
           LLAMA_PROMPT_FILE="$PROMPT_FILE" LLAMA_SYS_FILE="$SYS_FILE" \
           LLAMA_KEEP="$KEEP_REASONING" LLAMA_CTX="${CTX_SIZE:-16384}"

    # runner python 스크립트 생성 (임시)
    RUNNER=$(mktemp)
    cat > "$RUNNER" <<'PYEOF'
import json, os, sys, time, urllib.request, urllib.error

def load(f):
    if f: return open(f, encoding="utf-8").read()
    return ""

payload = {
  "model": "local",
  "messages": [],
  "max_tokens": 32768,
  "temperature": 0.6,
  "stream": False,
}
sys_t = load(os.environ.get("LLAMA_SYS_FILE"))
usr_t = load(os.environ.get("LLAMA_PROMPT_FILE"))
if sys_t: payload["messages"].append({"role":"system","content":sys_t})
payload["messages"].append({"role":"user","content":usr_t})

# max_tokens 는 컨텍스트 안에서 결정 (한 번에 생성 가능 t/한계는 슬롯 ctx 근처)
try:
    ctx = int(os.environ.get("LLAMA_CTX", "16384"))
except Exception:
    ctx = 16384
# 프롬프트/기록이 컨텍스트를 이미 쓰므로 남는 여유만 생성 가능.
# 여기선 보수적으로 컴텍스트의 70% 정도까지 응답 허용(실제는 남는 공간만큼).
payload["max_tokens"] = max(256, int(ctx * 0.7))

job = os.environ["LLAMA_JOB"]
data = json.dumps(payload).encode()
req = urllib.request.Request(os.environ["LLAMA_EP"], data=data,
                             headers={"Content-Type":"application/json"})

with open(os.path.join(job,"request.json"),"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2)

try:
    with urllib.request.urlopen(req, timeout=None) as r:
        resp = json.load(r)
    with open(os.path.join(job,"raw.json"),"w",encoding="utf-8") as f:
        json.dump(resp,f,ensure_ascii=False,indent=2)
    ch = resp["choices"][0]["message"]
    content = ch.get("content") or ""
    reasoning = ch.get("reasoning_content") or ""
    with open(os.path.join(job,"content.md"),"w",encoding="utf-8") as f:
        f.write(content)
    if os.environ.get("LLAMA_KEEP") == "1" and reasoning:
        with open(os.path.join(job,"reasoning.md"),"w",encoding="utf-8") as f:
            f.write(reasoning)
    with open(os.path.join(job,"status.txt"),"w",encoding="utf-8") as f:
        f.write("done\n")
    print("DONE -> "+os.path.join(job,"content.md"), flush=True)
except Exception as e:
    with open(os.path.join(job,"status.txt"),"w",encoding="utf-8") as f:
        f.write("error: %s\n"%e)
    print("ERROR: %s"%e, flush=True)
    sys.exit(1)
PYEOF

    LOG="$JOBDIR/run.log"
    nohup python3 "$RUNNER" >"$LOG" 2>&1 &
    BGPID=$!
    echo "$BGPID" > "$JOBDIR/pid"
    rm -f "$RUNNER"
    echo "==> 시작됨"
    echo "    job   : $JOBDIR"
    echo "    pid   : $BGPID (로그아웃해도 계속 실행)"
    echo "    상태  : bash overnight_gen.sh status $JOBDIR"
    echo "    결과  : $JOBDIR/content.md (완료 시)"
    ;;
  status)
    if [[ -n "${2:-}" ]]; then
      JOB="$2"
      echo "== job: $JOB"
      [[ -f "$JOB/status.txt" ]] && echo "   상태: $(cat "$JOB/status.txt")" || echo "   상태: (아직 진행 중)"
      [[ -f "$JOB/pid" ]]    && echo "   pid : $(cat "$JOB/pid")  ($(ps -o cmd= -p "$(cat "$JOB/pid")" 2>/dev/null || echo exited))"
      echo "   로그 꼬리:"
      tail -n 5 "$JOB/run.log" 2>/dev/null || true
      echo "   결과 파일 존재:"
      ls -la "$JOB" 2>/dev/null || true
    else
      echo "== 최근 jobs ($GEN_ROOT)"
      ls -1dt "$GEN_ROOT"/*/ 2>/dev/null | head -n 20 || echo "(none)"
    fi
    ;;
  *)
    echo "사용법:"
    echo "  bash overnight_gen.sh start <slug> <promptfile> [-s <systemfile>] [--keep-reasoning]"
    echo "  bash overnight_gen.sh status [jobdir]"
    exit 0
    ;;
esac
