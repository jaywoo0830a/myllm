#!/usr/bin/env bash
# ============================================================
# 05_install_systemd.sh
#   llama-server 를 상시 데몬(systemd)으로 등록한다.
#   - sudo 필요 (systemd 유닛 설치)
#   - 템플릿의 {{USER}}/{{SCRIPT_DIR}}/{{RUN_SCRIPT}} 치환
#   - enable + start
#
# 사용법:
#   bash 05_install_systemd.sh
#   # 이후 관리
#   systemctl status myllm-llama
#   journalctl -u myllm-llama -f
#   sudo systemctl restart myllm-llama
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SERVER_DIR="$(dirname "$SCRIPT_DIR")"   # .../server
TEMPLATE="$REPO_SERVER_DIR/systemd/myllm-llama.service"
DEST="/etc/systemd/system/myllm-llama.service"

[[ -f "$TEMPLATE" ]] || { echo "[!!] 템플릿 없음: $TEMPLATE" >&2; exit 1; }

RUN_SCRIPT="$SCRIPT_DIR/03_run_server.sh"
USER_NAME="$(whoami)"

echo "==> 유닛 생성: $DEST"
echo "    User     = $USER_NAME"
echo "    ScriptDir= $SCRIPT_DIR"

sed -e "s|{{USER}}|$USER_NAME|g" \
    -e "s|{{WORKDIR}}|$SCRIPT_DIR|g" \
    -e "s|{{RUN_SCRIPT}}|$RUN_SCRIPT|g" \
    "$TEMPLATE" | sudo tee "$DEST" >/dev/null

echo "==> systemd 리로드 + enable + start"
sudo systemctl daemon-reload
sudo systemctl enable myllm-llama
sudo systemctl restart myllm-llama

echo ""
echo "==> 상태 확인 (모델 로드에 수십 초~수 분 걸릴 수 있음):"
systemctl --no-pager status myllm-llama || true
echo ""
echo "로드 로그 보기: journalctl -u myllm-llama -f"
echo "스모크 테스트:   bash $SCRIPT_DIR/test_server.sh"
