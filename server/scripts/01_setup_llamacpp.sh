#!/usr/bin/env bash
# ============================================================
# 01_setup_llamacpp.sh
#   베어메탈 서버(Ubuntu)에서 llama.cpp 를 빌드한다.
#   - Zen5(9700X)용 AVX-512 빌드
#   - 최신 master 빌드 (Qwen3.5 'qwen35' hybrid arch 지원 필요)
#   - idempotent: 재실행해도 안전
#
# 사용법:
#   source ../config/env          # (env.example -> env 복사 후)
#   bash 01_setup_llamacpp.sh
# ============================================================
set -euo pipefail

# --- 1) 공통 설정 로드 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/config/env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "[!!] 환경설정 없음: server/config/env.example -> env 복사 후 편집하세요." >&2
  exit 1
fi

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
JOBS="$(nproc)"

echo "==> llama.cpp 디렉토리: $LLAMA_CPP_DIR"

# --- 2) 시스템 패키지 설치 ---
command -v cmake >/dev/null 2>&1 || {
  echo "==> 시스템 패키지 설치 (cmake 등) - sudo 필요"
  sudo apt-get update
  sudo apt-get install -y build-essential cmake git curl
}

# --- 3) llama.cpp 클론 / 갱신 ---
if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
  echo "==> llama.cpp 클론"
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
else
  echo "==> llama.cpp 최신화 (git pull)"
  git -C "$LLAMA_CPP_DIR" fetch --all && git -C "$LLAMA_CPP_DIR" pull --ff-only || true
fi

# --- 4) CMake 빌드 (AVX-512, 최신 arch) ---
BUILD_DIR="$LLAMA_CPP_DIR/build"
echo "==> CMake configure + build (관리자/CPU, AVX-512)"
cmake -S "$LLAMA_CPP_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=ON \
  -DLLAMA_CURL=ON \
  -DLLAMA_LLAMAFILE=ON \
  -DGGML_AVX512=ON

cmake --build "$BUILD_DIR" --config Release -j"$JOBS"

# llama-server 산출물 심볼릭 링크를 PATH 로 쓰기 쉽게
ln -sf "$BUILD_DIR/bin/llama-server" "$LLAMA_CPP_DIR/llama-server"
ln -sf "$BUILD_DIR/bin/llama-cli"    "$LLAMA_CPP_DIR/llama-cli"

echo ""
echo "==> 완료. 버전 확인:"
"$LLAMA_CPP_DIR/llama-server" --version

echo ""
echo "다음 단계: bash 02_download_model.sh   (GGUF 다운로드)"
