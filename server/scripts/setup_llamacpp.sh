#!/usr/bin/env bash
# ============================================================
# setup_llamacpp.sh — Build llama.cpp (CMake) for the server
#   This script clones the llama.cpp repo (if not already present) and
#   builds the `llama-server` binary using CMake.
#   It is idempotent – running it again will rebuild only if sources
#   have changed.
# ============================================================

set -euo pipefail

# Directory where llama.cpp will be installed (default: $HOME/llama.cpp)
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"

# Ensure CMake and a recent compiler are installed (Debian/Ubuntu)
if ! command -v cmake >/dev/null 2>&1; then
  echo "[info] Installing build dependencies..."
  sudo apt-get update -y && sudo apt-get install -y build-essential cmake git
fi

# Clone the repository if it does not exist
if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
  echo "[info] Cloning llama.cpp into $LLAMA_CPP_DIR"
  git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR"
fi

cd "$LLAMA_CPP_DIR"

# Pull latest changes (optional, safe if repo already cloned)
git fetch --all && git reset --hard origin/master

# Create a build directory
mkdir -p build && cd build

# Configure with CMake – enable the server and AVX‑512 if supported
cmake .. -DLLAMA_SERVER=ON -DLLAMA_AVX512=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-march=native -mtune=native -O3 -ffast-math -funroll-loops -fno-finite-math-only" -DCMAKE_CXX_FLAGS="-march=native -mtune=native -O3 -ffast-math -funroll-loops -fno-finite-math-only"

# Build all targets (llama-server, ggml, etc.)
make -j$(nproc)

# Verify that the server binary exists (CMake puts it in the build/bin/ directory)
SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"
if [[ -x "$SERVER_BIN" ]]; then
  # Copy to the location expected by the server scripts (LLAMA_SERVER defaults to $HOME/llama.cpp/llama-server)
  cp "$SERVER_BIN" "$LLAMA_CPP_DIR/llama-server"
  echo "[info] llama-server built and copied to $LLAMA_CPP_DIR/llama-server"
else
  echo "[error] Build failed – llama-server not found at $SERVER_BIN" >&2
  exit 1
fi

