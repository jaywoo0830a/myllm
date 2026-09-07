#!/usr/bin/env bash
# ============================================================
# restart.sh <slug>   —  "다 초기화하고 다시 띄우기" (깨끗한 재기동)
#
#   이미 실패(auto-restart 루프)했거나 중복 프로세스가 꼬인 경우에 유용.
#   아래를 순서대로 수행:
#     1) 기존 llama-server 유저 프로세스 전부 정리
#     2) systemd 실패 상태 reset + unit 재시작
#     3) 상태/로그 확인 (KV 옵션 미지원이면 run_one.sh 가 자동 경고 후 시작)
#
# 사용법:
#   bash restart.sh deepseek-r1-14b
#
# 관리용 개별 명령 원하면:
#   sudo systemctl stop myllm-llama@<slug>
#   sudo systemctl reset-failed myllm-llama@<slug>
#   sudo systemctl start myllm-llama@<slug>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG="${1:?사용법: bash restart.sh <slug> (예: deepseek-r1-14b)}"

UNIT="myllm-llama@${SLUG}.service"

echo "==> [1/4] 기존 llama-server 유저 프로세스 정리"
# 이 서비스를 제외하고 우연히 떠 있는 llama-server(엮인 옛 모델 등) 종료
pkill -TERM -f 'llama-server' 2>/dev/null || true
sleep 1
pkill -KILL -f 'llama-server' 2>/dev/null || true

echo "==> [2/4] systemd 실패 상태 리셋 + 유닛 재시작"
sudo systemctl stop "$UNIT" 2>/dev/null || true
sudo systemctl reset-failed "$UNIT" 2>/dev/null || true
sudo systemctl restart "$UNIT"

echo "==> [3/4] 상태 확인 (로드 수 분 걸릴 수 있음)"
sleep 2
systemctl --no-pager status "$UNIT" || true

echo ""
echo "==> [4/4] 시작 직후 로그 (KV/etc 경고 확인)"
journalctl -u "$UNIT" -n 30 --no-pager

echo ""
echo "==> 완료. 계속 보려면:  journalctl -u $UNIT -f"
echo "==> 정상 동작 확인:      bash $SCRIPT_DIR/test_server.sh $SLUG"
