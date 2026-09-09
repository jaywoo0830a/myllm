#!/usr/bin/env bash
# start_all.sh — on-demand 전략에 맞춘 "상시 최소"만 로드
# Usage: ./start_all.sh
#
# CPU 9700X (8C/16T) · DDR5 64GB 기준 (MODEL-ANALYSIS.md §1.5 / PLAN 동시로딩)
#   디코딩은 "메모리 대역폭 결합"(M1)이라 프로세스 개수를 늘려도 총 처리량은
#   늘지 않고 RAM/스레드만 낭비한다. 따라서 각 역할별 "대표 인스턴스 1개"만 상시.
#
#   상시 상주   : parser + worker1 + coder1   (각 역할 대표, 7B, ~15GB)
#   on-demand   : worker2~4, coder2~4, reasoner → bash scripts/up.sh <slug>
#   14B 상호배타: setter(8091) / judge(8092) 는 PLAN 대로 "둘 중 하나만" 단독 로드.
#                 → bash scripts/start_heavy.sh setter | judge
# --------------
#   같은 GGUF 추가 인스턴스(worker2~4, coder2~4)는 필요한 만큼만 올리고,
#   되도록 상시 인스턴스의 --parallel 슬롯으로 처리하면 RAM 을 아낀다.
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

# Load base environment first
load_base_env

# 상시 로드할 모델(각 역할의 대표 1개씩). 나머지는 필요시 개별 on-demand.
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
echo "   on-demand: bash scripts/up.sh worker2|coder2|reasoner ..."
echo "   14B 단독 : bash scripts/start_heavy.sh setter | judge"
