#!/usr/bin/env bash
# ============================================================
# 02_setup_diffusecpp.sh
#   베어메탈 서버(Ubuntu)에서 diffuse-cpp 를 빌드한다.
#
#   diffuse-cpp = Diffusion LLM(Dream-v0 / LLaDA-8B) 전용 CPU 추론 엔진
#     (llama.cpp 가 자회귀 AR 전용이라 diffusion 모델은 이 엔진으로 돌린다)
#   - Dream-7B: Qwen2.5 backbone, GQA, non-causal attention(bidirectional)
#   - llama.cpp 의 llama-diffusion-cli 와 별개의 독립 엔진 (GGML 기반)
#
#   산출물:
#     build/diffuse-cli          CLI 추론 (diffusion)
#     build/diffuse-quantize     GGUF 양자화
#     build/diffuse-bench        벤치
#
#   idempotent: 재실행해도 안전 (이미 있으면 pull + rebuild)
#
# 사용법:
#   bash 02_setup_diffusecpp.sh
#   환경변수 재정의:   DIFFUSE_CPP_DIR=/path bash 02_setup_diffusecpp.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# (선택) 공통 env 에 DIFFUSE_CPP_DIR 를 정의했다면 로드
ENV_FILE="$(dirname "$SCRIPT_DIR")/config/env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE" || true
fi

REPO_URL="https://github.com/iafiscal1212/diffuse-cpp.git"
DIFFUSE_CPP_DIR="${DIFFUSE_CPP_DIR:-${HOME}/diffuse-cpp}"
JOBS="$(nproc)"

echo "==> diffuse-cpp 디렉토리: $DIFFUSE_CPP_DIR"

# --- 1) 시스템 패키지 ---
command -v cmake >/dev/null 2>&1 || {
  echo "==> 시스템 패키지 설치 (cmake 등) - sudo 필요"
  sudo apt-get update
  sudo apt-get install -y build-essential cmake git curl
}

# --- 2) 소스 클론 (GGML submodule 포함: --recursive 필수) ---
if [[ ! -d "$DIFFUSE_CPP_DIR/.git" ]]; then
  echo "==> diffuse-cpp 클론 (recursive, GGML submodule)"
  mkdir -p "$(dirname "$DIFFUSE_CPP_DIR")"
  git clone --recursive "$REPO_URL" "$DIFFUSE_CPP_DIR"
else
  echo "==> diffuse-cpp 최신화"
  git -C "$DIFFUSE_CPP_DIR" fetch --all
  git -C "$DIFFUSE_CPP_DIR" pull --ff-only || true
  echo "==> submodule 갱신"
  git -C "$DIFFUSE_CPP_DIR" submodule update --init --recursive || true
fi

# --- 3) CMake 빌드 (Release. GGML submodule 포함 자동) ---
BUILD_DIR="$DIFFUSE_CPP_DIR/build"
echo "==> CMake configure + build (Release, tools 포함)"
cmake -S "$DIFFUSE_CPP_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DDIFFUSE_BUILD_TESTS=OFF \
  -DDIFFUSE_BUILD_TOOLS=ON

cmake --build "$BUILD_DIR" --config Release -j"$JOBS"

# --- 4) 잇기 쉬운 심볼릭 링크 (llama.cpp 관례와 동일) ---
ln -sf "$BUILD_DIR/diffuse-cli"      "$DIFFUSE_CPP_DIR/diffuse-cli"
ln -sf "$BUILD_DIR/diffuse-quantize" "$DIFFUSE_CPP_DIR/diffuse-quantize"

echo ""
echo "==> 빌드 산출물:"
ls -la "$DIFFUSE_CPP_DIR/build"/diffuse-cli "$DIFFUSE_CPP_DIR/build"/diffuse-quantize 2>/dev/null || true
echo ""
echo "==> 설치 완료. GGUF 확보 다음 단계:"
echo "    (a) 사전 제작 GGUF:   diffuste-cpp/Dream-v0-Instruct-7B-GGUF (HF)"
echo "    (b) 직접 변환:  tools/convert-dream.py  (원본 safetensors 필요, torch 설치 필요)"
echo "    실행 예:  $DIFFUSE_CPP_DIR/diffuse-cli -m <dream.gguf> --tokens \"<id,...>\" -n 256 -s 16 -t 8 --remasking entropy_exit"
