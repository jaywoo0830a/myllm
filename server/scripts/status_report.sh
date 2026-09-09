#!/usr/bin/env bash
# =========================================================================
# status_report.sh — 현재 모델 상황을 STATUS.md 로 스냅샷 생성 (다른 팀 공유용)
#   Usage:
#     bash scripts/status_report.sh            # 저장소 내부 실행 (로컬 그대로)
#     bash scripts/status_report.sh --remote   # 이 서버가 아니어도, 저장소만 있으면 실행
#     bash scripts/status_report.sh -o custom.md
#
#   생성 내용 (STATUS.md)
#     1) 시스템 요약 (CPU/RAM — 이 서버에서 돌리면 실제값, 아니면 저장소 기준)
#     2) 모델별 상태 테이블: 역할 / GGUF / 포트 / ↑↓ / PID(RSS) / 실제 실행 옵션
#        - pid 파일(run/*.pid) + /proc/<pid> 로 생사 판정
#        - 실행 중이면 /proc/<pid>/cmdline 에서 실제 llama-server 옵션 추출
#     3) 상주 메모리 합계 + 권장 상태와의 비교
#     4) "이상적으로 어떻게 써야 하는지" 가이드
#
#   다른 팀은 이 출력만 봐도 어떤 모델이 떠 있고 메모리가 얼마나 남았는지,
#   뭘 키고/내려야 하는지 즉시 알 수 있다.
# =========================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# ---- 인자 파싱 -------------------------------------------------------------
REMOTE=false
OUT="STATUS.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE=true; shift ;;
    -o|--output) OUT="$2"; shift 2 ;;
    *) echo "[ERR] 알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

OUT_ABS="$OUT"
# 기본 출력(STATUS.md)은 저장소 루(server/스크립트의 부모의 부모)에 둔다.
#   scripts/status_report.sh → <repo>/STATUS.md
if [[ "$OUT" == "STATUS.md" ]]; then
  OUT_ABS="${SCRIPT_DIR}/../.."
  OUT_ABS="$(cd "$OUT_ABS" && pwd)/${OUT}"
elif [[ "$OUT" != /* ]]; then
  OUT_ABS="${SCRIPT_DIR}/../${OUT}"
fi

# ---- 시스템 요약 ------------------------------------------------------------
detect_cpu() {
  local m
  m="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')"
  local cores threads
  cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '?')"
  threads="$(nproc 2>/dev/null || echo '?')"
  if [[ -n "$m" ]]; then echo "$m  (cores=$cores, threads=$threads)"; else echo "알 수 없음(remote)"; fi
}

detect_mem() {
  local total_kb avail_kb used_kb
  total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
  avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
  if [[ -n "$total_kb" && -n "$avail_kb" ]]; then
    used_kb=$(( total_kb - avail_kb ))
    printf "total=%s GB, used=%s GB, avail=%s GB" \
      "$(awk -v v=$total_kb 'BEGIN{printf "%.1f", v/1048576}')" \
      "$(awk -v v=$used_kb  'BEGIN{printf "%.1f", v/1048576}')" \
      "$(awk -v v=$avail_kb 'BEGIN{printf "%.1f", v/1048576}')"
  else
    echo "remote(저장소 예상값 사용)"
  fi
}

# ---- 모델 목록 + 헬퍼 -------------------------------------------------------
declare -a SLUGS=( parser worker1 worker2 worker3 worker4 coder1 coder2 coder3 coder4 reasoner setter judge )

role_of() {
  case "$1" in
    parser)   echo "분배(Parser)" ;;
    worker*)  echo "일꾼(Worker)" ;;
    coder*)   echo "코더(Coder)" ;;
    reasoner) echo "추론가(Reasoner)" ;;
    setter)   echo "문제생성(Setter/14B)" ;;
    judge)    echo "판사(Judge/14B)" ;;
    *) echo "기타" ;;
  esac
}
gguf_of()  { grep -E "^MODEL_FILE=" "${SERVER_CONFIG_DIR}/models/$1.env" 2>/dev/null | cut -d= -f2- || echo "?"; }
port_of()  { grep -E "^LLAMA_PORT=" "${SERVER_CONFIG_DIR}/models/$1.env" 2>/dev/null | cut -d= -f2- || echo "?"; }

running_opts() {
  local pidfile="${SCRIPT_DIR}/../run/$1.pid" pid
  [[ -f "$pidfile" && -s "$pidfile" ]] || { echo "-"; return; }
  pid="$(cat "$pidfile")"
  if [[ -r "/proc/$pid/cmdline" ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" | sed 's/--/\n    --/g' \
      | grep -E -- '--parallel|--ctx-size|--cache-type|-b |-ub |--alias|-t ' | tr '\n' ' '
  else
    echo "remote(pid=$pid)"
  fi
}

# ---- 메인 생성 --------------------------------------------------------------
{
  echo "# STATUS — 현재 모델 운용 현황"
  echo
  echo "> 생성: $(date '+%Y-%m-%d %H:%M:%S %Z')  ·  호스트: $(hostname 2>/dev/null || echo '?')"
  echo "> (이 서버에서 실행 시 실제 프로세스/메모리 기준, \`--remote\` 면 저장소 기준)"
  echo

  # 1) 시스템 요약
  echo "## 1. 시스템 요약"
  echo
  echo "| 항목 | 값 |"
  echo "|---|---|"
  echo "| CPU | $(detect_cpu) |"
  echo "| RAM | $(detect_mem) |"
  echo "| 스왑 | $(awk '/^SwapTotal:/{printf \"%.1f GB\", $2/1048576}' /proc/meminfo 2>/dev/null || echo '-') |"
  echo "| 설계 기준(ideal) | 9700X(8C/16T) · DDR5 64GB · CPU-only |"
  echo

  # 2) 모델별 상태
  echo "## 2. 모델별 상태"
  echo
  echo "| 역할 | 모델(GGUF) | 포트 | 상태 | PID | RSS(MB) | 실제 실행 옵션(일부) |"
  echo "|---|---|---|---|---|---|---|"
  total_rss=0
  for s in "${SLUGS[@]}"; do
    pid="-" st="▼(down)" rss=0 opts="-"
    pidfile="${SCRIPT_DIR}/../run/$s.pid"
    if [[ -f "$pidfile" && -s "$pidfile" ]]; then
      pid="$(cat "$pidfile")"
      if kill -0 "$pid" 2>/dev/null; then
        st="▲(up)"
        rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null)
        rss=$(( ${rss:-0} / 1024 ))
        opts="$(running_opts "$s")"
        total_rss=$(( total_rss + rss ))
      else
        st="⚠(pid 존재/미실행)"
      fi
    fi
    gguf="$(basename "$(gguf_of "$s")")"
    echo "| $(role_of "$s") | \`$gguf\` | $(port_of "$s") | $st | $pid | $rss | $opts |"
  done
  echo

  # 3) 메모리 요약
  echo "## 3. 메모리 요약"
  echo
  echo "- 실행 중 llama-server RSS 합계 ≈ **${total_rss} MB** (위 표)."
  echo "- OS/RAG/캐시 포함 전체 사용량은 1번 시스템 요약의 RAM used 를 보세요."
  echo

  # 4) 권장 상태와 비교
  echo "## 4. 권장 상태 대비 현재"
  echo
  echo "| 구분 | 권장 상주 | 실행 |"
  echo "|---|---|---|"
  echo "| 상시 | parser + worker1 + coder1 (≈15GB) | \`bash scripts/start_all.sh\` |"
  echo "| on-demand | worker2~4, coder2~4, reasoner | \`bash scripts/up.sh <slug>\` |"
  echo "| 14B 상호배타 | setter ↔ judge (둘 중 하나만) | \`bash scripts/start_heavy.sh setter\\|judge\` |"
  echo
  echo "> 현재 떠 있는(▲) 모델이 위 권장과 다르면 불필요한 인스턴스를 내리세요:"
  echo '>   `bash scripts/down.sh <slug>`'
  echo

  # 5) 이상적 사용 가이드
  echo "## 5. 이상적으로 어떻게 써야 하는가"
  echo
  cat <<'GUIDE'
**핵심 원리 (수학: `MODEL-ANALYSIS.md` §1)**
- 디코딩(토큰 생성)은 **메모리 대역폭 결합**입니다. 프로세스를 병렬로 늘려도 총 처리량은
  늘지 않고 RAM·스레드만 낭비되어 오히려 느려집니다.
- 그래서 **"상시 = 역할별 대표 1개씩만, 14B = 둘 중 하나만(단독)"** 이 원칙입니다.

**역할별 로드 가이드**
| 목적 | 실행 |
|---|---|
| 요약/검색/분배 | `bash scripts/start_all.sh` (parser+worker1+coder1) |
| 추가 일꾼(요약 병렬) | `bash scripts/up.sh worker2` |
| 코드 작성/리뷰/픽스 | 상시 coder1 (필요시 worker2~4 처럼 up.sh) |
| 딥추론/증명(긴 출력) | `bash scripts/up.sh reasoner` (최대 2000tok → CPU 에선 수 분) |
| 문제 생성(14B) | `bash scripts/start_heavy.sh setter` (독점) |
| 검증(14B, GBNF) | `bash scripts/start_heavy.sh judge` (setter 와 배타) |

**속도 가이드 (CPU 9700X)**
- 7B(Q4): **~7–9 tok/s** · 14B(Q5): **~4–5 tok/s**
- "판사 1초"는 GBNF 로 출력은 짧으나 **입력 프리필 때문에 총 5–10초**가 현실적 SLA.
- 여러 역할에 요청을 흩뿌리지 말고 **한 번에 한 흐름**으로 굴리면 각 응답이 빨라집니다.
GUIDE
  echo
  echo "---"
  echo "*생성 스크립트: \`server/scripts/status_report.sh\` · 상세 자원 모델: \`MODEL-ANALYSIS.md\`*"
} > "$OUT_ABS"

echo "✅ $OUT_ABS 생성 완료 (이 파일을 다른 팀과 공유하세요)"
echo "   재생성: bash server/scripts/status_report.sh [--remote]"