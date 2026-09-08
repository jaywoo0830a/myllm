#!/usr/bin/env bash
# ============================================================
# download_all.sh
#   모델 폴더(config/models/*.env, *.env.example)의 모든 모델을 한 번에 다운로드
#   - 각 파일의 HF_REPO 와 MODEL_FILE 을 읽어 HuggingFace 에서 GGUF 를 받습니다
#   - download.sh 와 동일한 경로 규약을 사용합니다:
#       * 최종 저장 위치 : ${MODEL_DIR:-~/models}/<MODEL_FILE basename>
#       * MODEL_FILE 앞의 디렉터리 접두(예: ${MODEL_DIR}/)는 basename 으로 정규화
#   - 중복 파일(worker1..4 처럼 같은 GGUF 를 여러 인스턴스에 쓰는 경우)은
#     한 번만 받고 나머지는 skip 합니다
#   - 토큰은 lib.sh 의 resolve_hf_token 순서로 찾습니다
#       HF_TOKEN → server/config/hf_token → ~/.cache/huggingface/token
#   - 다운로더 우선순위: aria2c(병렬) → curl(fallback)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

CONFIG_DIR="${SERVER_CONFIG_DIR}/models"
MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
mkdir -p "${MODEL_DIR}"

TOKEN="$(resolve_hf_token)"
TOKEN_HDR=()
if [[ -n "$TOKEN" ]]; then
  TOKEN_HDR=(--header "Authorization: Bearer ${TOKEN}")
fi

PARALLEL="${HF_DL_THREADS:-8}"

# KEY=VALUE 추출 (모든 일치 중 마지막, 공백/CR 제거)
get_key() {
  local file=$1 key=$2
  grep -E "^${key}=" "$file" | cut -d'=' -f2- | tr -d '[:space:]' | tail -n1
}

# 다운로드 함수: aria2c → curl
download_one() {
  local url=$1 out_path=$2 log_path=$3
  local name; name="$(basename "$out_path")"
  if [[ -f "$out_path" ]]; then
    echo "✅ SKIP (이미 존재) : ${name}"
    return 0
  fi
  echo "⬇️  ${name}"
  echo "        ${url}"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -x "$PARALLEL" -s "$PARALLEL" -k 1M -c \
      "${TOKEN_HDR[@]}" \
      --max-tries=3 --retry-wait=3 --console-log-level=warn \
      -d "${MODEL_DIR}" -o "$name" "$url" --log="$log_path" \
      || { echo "❌ aria2c 실패: ${name} (로그: $log_path)" >&2; return 1; }
  elif command -v curl >/dev/null 2>&1; then
    curl -L --fail -C - "${TOKEN_HDR[@]}" "$url" -o "$out_path" \
      || { echo "❌ curl 실패: ${name}" >&2; return 1; }
  else
    echo "❌ aria2c 와 curl 이 모두 없습니다. 하나를 설치하세요." >&2
    return 1
  fi
  echo "✅ ${name}"
  return 0
}

# config 경로의 모든 *.env / *.env.example 수집
shopt -s nullglob
files=("${CONFIG_DIR}"/*.env "${CONFIG_DIR}"/*.env.example)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "❌ ${CONFIG_DIR} 아래에 *.env / *.env.example 가 없습니다." >&2
  exit 1
fi

# 중복 다운로드 방지: target 파일 이름이 겹치면 첫 파일만 실제 다운로드
declare -A seen=()
declare -a jobs=()

for f in "${files[@]}"; do
  base="$(basename "$f")"
  slug="${base%.env.example}"
  slug="${slug%.env}"
  hf_repo="$(get_key "$f" "HF_REPO")"
  raw_file="$(get_key "$f" "MODEL_FILE")"
  if [[ -z "$hf_repo" || -z "$raw_file" ]]; then
    echo "⚠️  ${base}: HF_REPO 또는 MODEL_FILE 누락 → 건너뜀"
    continue
  fi
  name="$(basename "$raw_file")"
  out="${MODEL_DIR}/${name}"
  url="https://huggingface.co/${hf_repo}/resolve/main/${name}"
  if [[ -z "${seen[$name]:-}" ]]; then
    seen[$name]="$base"
    jobs+=("$base|$url|$out")
  else
    echo "ℹ️  ${base}: ${name} 는 ${seen[$name]} 와 동일 파일 → 대기열 제외(공유)"
  fi
done

echo "── 대상 모델 ${#jobs[@]}개 ──────────────────────────────"
rc=0
for job in "${jobs[@]}"; do
  IFS='|' read -r slug url out <<< "$job"
  log="${MODEL_DIR}/${slug}.download.log"
  if [[ -f "$out" ]]; then
    echo "✅ SKIP (이미 존재) : $(basename "$out")"
    continue
  fi
  if ! download_one "$url" "$out" "$log"; then
    echo "❌  ${slug} 다운로드 실패" >&2
    rc=1
  fi
done

echo "🚀  전부 끝났습니다. (실패 시 exit=$rc / 저장위치: ${MODEL_DIR})"
exit "$rc"
