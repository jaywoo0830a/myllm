#!/usr/bin/env bash
# start_heavy.sh — 14B 헤비 모델을 "상호배타(mutual exclusion)"로 단독 로드
#   Usage: bash scripts/start_heavy.sh setter
#          bash scripts/start_heavy.sh judge
#
# 14B 모델(Setter ~11GB, Judge ~11GB)은 RAM+대역폭이 커서 두 개를 동시에
# 띄우면 OOM/스왑 위험이 크다 (MODEL-ANALYSIS.md P1, PLAN 동시로딩 전략).
# 따라서 "둘 중 하나만" 떠 있도록, 이웃 14B 를 먼저 내린 후 대상만 로드한다.
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

TARGET="${1:-}"
case "${TARGET}" in
    setter) OTHER="judge" ;;
    judge)  OTHER="setter" ;;
    "")
        echo "❌ Usage: bash scripts/start_heavy.sh setter | judge" >&2
        exit 2
        ;;
    *)
        echo "❌ 알 수 없는 14B 모델 '${TARGET}'. setter 또는 judge 만 지원합니다." >&2
        exit 2
        ;;
esac

# 1) 상호배타: 반대 14B 가 떠 있으면 먼저 내린다
OTHER_PID_FILE="${SCRIPT_DIR}/../run/${OTHER}.pid"
if [[ -f "${OTHER_PID_FILE}" && -s "${OTHER_PID_FILE}" ]]; then
    echo "↩ 14B 상호배타: ${OTHER} 를 먼저 내립니다 (${OTHER} → ${TARGET} 로 전환)"
    "${SCRIPT_DIR}/down.sh" "${OTHER}"
fi

# 2) 대상 14B 단독 로드
echo "🚀 ${TARGET} 단독 로드 시작..."
"${SCRIPT_DIR}/up.sh" "${TARGET}"

echo "✅ ${TARGET} 단독 로드 완료 (메모리 여유 확보)"
echo "   다른 14B(${OTHER}) 가 필요하면: bash scripts/start_heavy.sh ${OTHER}"