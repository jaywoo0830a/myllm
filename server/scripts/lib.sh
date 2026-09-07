# ============================================================
# lib.sh  —  공통 헬퍼 (source 해서 사용)
#   로드 순서: config/env(base) -> config/models/<slug>.env(모델)
#   용법(스크립트 상단에서):
#     SCRIPT_DIR=...(자기 위치)
#     # shellcheck disable=SC1091
#     source "$SCRIPT_DIR/lib.sh"
#     load_base_env
#     load_model_env "${MODEL_NAME:?사용법: MODEL_NAME=... 또는 인자}"
# ============================================================

# lib.sh 자신의 위치 기준 경로 결정
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_DIR="${_LIB_DIR}/../config"
export SERVER_CONFIG_DIR

# load_base_env: config/env 로드 (없으면 .example 복사 안내 후 기본값 사용 가능)
load_base_env() {
  local ENV_FILE="$SERVER_CONFIG_DIR/env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  else
    echo "[warn] $ENV_FILE 없음. server/config/env.example 을 참고해 생성하세요." >&2
    LLAMA_HOST="${LLAMA_HOST:-0.0.0.0}"
    MODEL_DIR="${MODEL_DIR:-${HOME}/models}"
    LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/llama.cpp}"
  fi
}

# load_model_env <slug>: config/models/<slug>.env 로드 (없으면 .example 안내)
#   성공 시 MODEL_NAME, ALIAS, HF_REPO, MODEL_FILE, LLAMA_PORT 등이 채워짐.
load_model_env() {
  local slug="${1:?load_model_env: slug 필요}"
  local f="$SERVER_CONFIG_DIR/models/${slug}.env"
  if [[ ! -f "$f" ]]; then
    echo "[!!] 모델 프로파일 없음: $f" >&2
    echo "    참고: cp server/config/models/${slug}.env.example $f" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$f"
  # 필수 검증
  : "${MODEL_NAME:?없음: MODEL_NAME}"
  : "${ALIAS:?없음: ALIAS}"
  : "${HF_REPO:?없음: HF_REPO}"
  : "${MODEL_FILE:?없음: MODEL_FILE}"
  : "${LLAMA_PORT:?없음: LLAMA_PORT}"
  # 기본값
  CTX_SIZE="${CTX_SIZE:-16384}"
  NO_THINK="${NO_THINK:-0}"
  THREADS="${THREADS:-0}"
  PARALLEL="${PARALLEL:-1}"
  BATCH="${BATCH:-512}"
  UBATCH="${UBATCH:-512}"
}

# resolve_hf_token: HF_TOKEN / hf_token 파일 / ~/.cache/huggingface/token 순서
resolve_hf_token() {
  if [[ -n "${HF_TOKEN:-}" ]]; then echo "$HF_TOKEN"; return; fi
  local tf="$SERVER_CONFIG_DIR/hf_token"
  if [[ -f "$tf" ]]; then tr -d ' \t\r\n' < "$tf"; return; fi
  local hub="$HOME/.cache/huggingface/token"
  if [[ -f "$hub" ]]; then tr -d ' \t\r\n' < "$hub"; return; fi
  echo ""
}

# model_gguf_path: 다운로드될/된 GGUF 절대경로
model_gguf_path() {
  echo "${MODEL_DIR}/${MODEL_FILE}"
}

# print_model_summary
print_model_summary() {
  echo "모델: ${MODEL_NAME}  (alias=${ALIAS})"
  echo "  repo : ${HF_REPO} :: ${MODEL_FILE}"
  echo "  port : ${LLAMA_HOST}:${LLAMA_PORT}  ctx=${CTX_SIZE}"
  echo "  path : $(model_gguf_path)"
}
