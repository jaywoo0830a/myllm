#!/usr/bin/env bash
# ------------------------------------------------------------
# download_all.sh
#   모든 *.env 및 *.env.example 파일에 정의된 모델을 한 번에 다운로드
#   - HF_REPO와 MODEL_FILE 를 읽어 HuggingFace에서 GGUF 파일을 가져옵니다
#   - HF_TOKEN 환경 변수가 있으면 인증 헤더를 추가합니다 (DeepSeek‑V2‑Chat 등)
#   - aria2c 가 있으면 병렬 다운로드, 없으면 curl 로 폴백합니다
#   - 파일이 이미 존재하면 스킵합니다
# ------------------------------------------------------------
set -euo pipefail

# 1️⃣  작업 디렉터리 설정
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BASE_DIR}/../config/models"
TARGET_DIR="${HOME}/models"
mkdir -p "${TARGET_DIR}"

# 2️⃣  토큰 설정 (선택)
HF_TOKEN="${HF_TOKEN:-}"

# 3️⃣  파일에서 KEY=VALUE 를 추출하는 함수
get_key() {
    local file=$1
    local key=$2
    grep -E "^${key}=" "$file" | cut -d'=' -f2- | tr -d '[:space:]'
}

# 4️⃣  다운로드 함수 (aria2c → curl)
download_one() {
    local url=$1
    local out_path=$2
    local log_path=$3
    # 이미 존재하면 스킵
    if [[ -f "$out_path" ]]; then
        echo "✅ Model already present at $out_path"
        return 0
    fi
    echo "⬇️  Downloading $(basename "$out_path") from $url"
    if command -v aria2c >/dev/null 2>&1; then
        if [[ -n "$HF_TOKEN" ]]; then
            aria2c --header="Authorization: Bearer ${HF_TOKEN}" -x8 -s8 -k1M -c -d "${TARGET_DIR}" -o "$(basename "$out_path")" "$url" --log="$log_path" || return 1
        else
            aria2c -x8 -s8 -k1M -c -d "${TARGET_DIR}" -o "$(basename "$out_path")" "$url" --log="$log_path" || return 1
        fi
    else
        if [[ -n "$HF_TOKEN" ]]; then
            curl -L -H "Authorization: Bearer ${HF_TOKEN}" -C - "$url" -o "$out_path" || return 1
        else
            curl -L -C - "$url" -o "$out_path" || return 1
        fi
    fi
    echo "✅ Download complete: $out_path"
    return 0
}

# 5️⃣  메인 루프 – *.env 와 *.env.example 모두 처리
shopt -s nullglob
env_files=("${CONFIG_DIR}"/*.env "${CONFIG_DIR}"/*.env.example)

if [[ ${#env_files[@]} -eq 0 ]]; then
    echo "❌ No *.env or *.env.example files found in $CONFIG_DIR"
    exit 1
fi

for env_file in "${env_files[@]}"; do
    # 파일 이름에서 슬러그 추출 (예: parser, worker1)
    slug="$(basename "$env_file" .env.example)"
    slug="${slug%.env}"
    hf_repo=$(get_key "$env_file" "HF_REPO")
    model_file=$(get_key "$env_file" "MODEL_FILE")
    if [[ -z "$hf_repo" || -z "$model_file" ]]; then
        echo "⚠️  $env_file 에서 HF_REPO 혹은 MODEL_FILE 을 찾지 못했습니다 → 건너뛰기"
        continue
    fi
    url="https://huggingface.co/${hf_repo}/resolve/main/${model_file}"
    out_path="${TARGET_DIR}/${model_file}"
    log_path="${TARGET_DIR}/${slug}.download.log"
    if ! download_one "$url" "$out_path" "$log_path"; then
        echo "❌  $slug 다운로드 실패! 로그: $log_path"
    fi
 done

echo "🚀  모든 모델 다운로드 시도가 끝났습니다."
