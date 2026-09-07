#!/usr/bin/env bash
# ============================================================
# install_models.sh
#   config/models/*.env 에 정의된 모든 모델을 systemd 인스턴스로
#   등록(+enable+start)한다. (재부팅 자동 기동)
#
#   생성 유닛: /etc/systemd/system/myllm-llama@<slug>.service
#
# 사용법:
#   bash install_models.sh                # 모든 활성 slug 설치·시작
#   bash install_models.sh qwen3-14b      # 특정 slug 만
#
# 관리:
#   systemctl status 'myllm-llama@*'
#   journalctl -u 'myllm-llama@qwen3-14b' -f
#   sudo systemctl restart myllm-llama@qwen3-14b
#   sudo systemctl stop myllm-llama@deepseek-1.5b
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$SERVER_DIR/config/models"
TEMPLATE="$SERVER_DIR/systemd/myllm-llama@.service"

[[ -f "$TEMPLATE" ]] || { echo "[!!] 템플릿 없음: $TEMPLATE" >&2; exit 1; }
USER_NAME="$(whoami)"

# slug 선택
if [[ -n "${1:-}" ]]; then
  SLUGS=("$1")
else
  mapfile -t SLUGS < <(ls "$MODELS_DIR"/*.env 2>/dev/null | xargs -n1 basename | sed 's/\.env$//' | sort)
fi
if [[ ${#SLUGS[@]} -eq 0 ]]; then
  echo "[!!] config/models/*.env 없음 (설치할 모델 없음). 하위 .example 참고해 env 복사." >&2
  exit 1
fi

for s in "${SLUGS[@]}"; do
  [[ -f "$MODELS_DIR/${s}.env" ]] || { echo "[skip] $s : ${s}.env 없음" >&2; continue; }
  tmp="$(mktemp)"
  sed -e "s|{{USER}}|$USER_NAME|g" \
      -e "s|{{SCRIPT_DIR}}|$SCRIPT_DIR|g" \
      "$TEMPLATE" > "$tmp"
  echo "==> [${s}] 인스턴스 유닛 install + enable + start"
  sudo install -m 644 "$tmp" "/etc/systemd/system/myllm-llama@${s}.service"
  rm -f "$tmp"
done

echo "==> daemon-reload"
sudo systemctl daemon-reload
for s in "${SLUGS[@]}"; do
  [[ -f "$MODELS_DIR/${s}.env" ]] || continue
  echo "==> [${s}] enable --now"
  sudo systemctl enable "myllm-llama@${s}.service"
  sudo systemctl restart "myllm-llama@${s}.service"
done

echo ""
echo "==> 상태:"
systemctl --no-pager status 'myllm-llama@*' || true
echo ""
echo "로그: journalctl -u 'myllm-llama@<slug>' -f"
echo "스모크: bash $SCRIPT_DIR/test_server.sh <slug>   (또는 LLAMA_PORT 지정)"
