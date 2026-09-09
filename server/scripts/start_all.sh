#!/usr/bin/env bash
# start_all.sh — CPU 환경에 맞춘 "상시 최소"만 로드
# Usage: ./start_all.sh
#
# CPU 9700X (8C/16T) · DDR5 64GB 기준 (MODEL-ANALYSIS.md §1.5 / PLAN 동시로딩)
#   디코딩은 "메모리 대역폭 결합"(M1)이라 프로세스 개수를 늘려도 총 처리량은
#   늘지 않고 RAM/스레드만 낭비한다. 따라서 역할마다 "대표 인스턴스 1개"만 상시
#   띄우고, 병렬(worker2~4, coder2~4) 은 아예 만들지 않는다.
#
#   상시 상주   : parser + worker1 + coder1   (각 역할 대표 1개, 7B, ~15GB)
#   on-demand   : reasoner → bash scripts/up.sh reasoner
#   14B 상호배타: setter(8091) / judge(8092) 는 PLAN 대로 "둘 중 하나만" 단독 로드.
#                 → bash scripts/start_heavy.sh setter | judge
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# Load base environment first
load_base_env

# 상시 로드할 모델(각 역할 대표 1개). 나머지(reasoner)는 필요시 개별 on-demand.
SLUGS=(
    parser
    worker1
    coder1
)

for SLUG in "${SLUGS[@]}"; do
    echo "🚀 Starting model $SLUG (상시)..."
    "${SCRIPT_DIR}/up.sh" "$SLUG"
    # Give a short pause to avoid race conditions
    sleep 0.5
done

echo "✅ 상시 모델 로드 완료 (parser + worker1 + coder1)"
echo "   on-demand: bash scripts/up.sh reasoner"
echo "   14B 단독 : bash scripts/start_heavy.sh setter | judge"
