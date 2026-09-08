#!/usr/bin/env python3
"""diffuse_generate.py — diffuse-cpp(Dream-v0) 실행 래퍼 (myllm 도입판)

Dream/LLaDA 같은 **diffusion LLM** 전용. llama-server(AR, OpenAI)가 아니라
diffuse-cli 를 단일 호출한다. GGUF 는 ~/models/diffuse/dream-7b-q4km.gguf(등).

diffuse-cli 는 토크나이저를 내장하지 않으므로(그리고 stdout 에 생성 토큰 ID 를
쉼표 문자열로 돌려줌) 아래 단계를 감싼다:
  1) transformers AutoTokenizer 로 프롬프트(+chat template) 토큰화
  2) `diffuse-cli --tokens "<id,...>"` 서브프로세스 호출
  3) stdout 토큰 ID 목록을 마스크/특수토큰 제거 후 디코드해 텍스트 출력

사용법(서버에서):
  bash .../download_dream.sh 로 GGUF 확보 후:
  python3 diffuse_generate.py \\
      --gguf "$HOME/models/diffuse/dream-7b-q4km.gguf" \\
      --tokenizer "$HOME/models/dream-tokenizer" \\
      -p "What is the capital of France?" \\
      -n 256 -s 16 -t 8 --remasking entropy_exit

토크나이저 준비(--tokenizer):
  로컬 HF 파이프라인 없이 tokenizer.json 등만 내려받을 수 있다:
    mkdir -p ~/models/dream-tokenizer
    # HF 에서 원본 리포의 tokenizer.json / tokenizer_config.json / special_tokens_map.json
    # (+ Dream 은 sentencepiece tokenizer.model 일 수도) 을 다운로드.
  또는 이미 safetensors 전체를 받았으면 그 디렉토리를 넘기면 된다.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Dream diffusion 리마스킹에서 마스크/미결정 표시로 쓰이는 토큰 id.
# (diffuse-cli 스모크로 확인: Dream GGUF mask_token=151666 = "<|mask|>".)
DEFAULT_MASK_ID = 151666
# diffuse-cli 위치 기본은 diffuse-cpp symlink
DEFAULT_CPP_BIN = "diffuse-cli"


def _build_ld_path(cpp_bin: str) -> list[str]:
    """diffuse-cli 가 ggml 공유 라이브러리를 찾도록 LD_LIBRARY_PATH 보정."""
    exe = Path(cpp_bin)
    if exe.is_symlink():
        exe = exe.resolve()
    build_dir = str(exe.parent)                       # .../build
    ggml_lib = str(exe.parent / "ggml" / "src")       # .../build/ggml/src
    parts = [build_dir, ggml_lib]
    if "LD_LIBRARY_PATH" in os.environ:
        parts.append(os.environ["LD_LIBRARY_PATH"])
    return parts


def main() -> int:
    ap = argparse.ArgumentParser(
        description="diffuse-cpp(Dream-v0) diffusion 생성 래퍼")
    ap.add_argument("--gguf", "-m", required=True, help="Dream GGUF 경로")
    ap.add_argument("--tokenizer", required=True,
                    help="HF model id 또는 로컬 디렉토리(원본 Dream 토크나이저)")
    ap.add_argument("-p", "--prompt", required=True, help="user 프롬프트")
    ap.add_argument("--system", default="You are a helpful assistant.",
                    help="시스템 프롬프트")
    ap.add_argument("--raw", action="store_true",
                    help="chat template 없이 프롬프트 그대로 토큰화")
    ap.add_argument("--n", "-n", type=int, default=256, help="생성 토큰 수")
    ap.add_argument("--steps", "-s", type=int, default=16,
                    help="diffusion step 수 (기본16, entropy_exit 는 조기종료)")
    ap.add_argument("--threads", "-t", type=int, default=8,
                    help="스레드 (9700X 물리코어=8 권장)")
    ap.add_argument("--temp", type=float, default=0.0, help="온도 (0=argmax)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--schedule", default="cosine",
                    choices=["cosine", "linear"])
    ap.add_argument("--remasking", default="entropy_exit",
                    choices=["low_confidence", "random", "entropy_exit",
                             "maskgit_plus", "topk_margin"],
                    help="리컷 스케줄러 (Dream 권장: entropy_exit)")
    ap.add_argument("--entropy-threshold", type=float, default=1.5)
    ap.add_argument("--no-cache", action="store_true",
                    help="inter-step KV cache 끄기(느려짐)")
    ap.add_argument("--cache-refresh", type=int, default=0)
    ap.add_argument("--cache-keep-active", type=int, default=0)
    ap.add_argument("--cpp-bin", default=DEFAULT_CPP_BIN,
                    help="diffuse-cli 경로(기본 PATH/diffuse-cli)")
    ap.add_argument("--mask-id", type=int, default=DEFAULT_MASK_ID)
    args = ap.parse_args()

    if not Path(args.gguf).exists():
        print(f"[!!] GGUF 없음: {args.gguf}", file=sys.stderr)
        return 1

    # --- 토크나이저 ---
    try:
        from transformers import AutoTokenizer
    except ImportError:
        print("[!!] transformers 미설치. pip install transformers "
              "(래퍼는 diffuse-cli 용 토큰화에만 필요)", file=sys.stderr)
        return 1

    print(f"토크나이저 로드: {args.tokenizer}", file=sys.stderr)
    tok = AutoTokenizer.from_pretrained(args.tokenizer, trust_remote_code=True)

    if args.raw:
        input_ids = tok.encode(args.prompt)
    else:
        msgs = [
            {"role": "system", "content": args.system},
            {"role": "user", "content": args.prompt},
        ]
        ids = None
        try:
            r = tok.apply_chat_template(
                msgs, add_generation_prompt=True, tokenize=True)
            # transformers 5.x: BatchEncoding(느슨한 dict) 반환 가능 → input_ids 추출
            if hasattr(r, "input_ids"):
                ids = list(r.input_ids)
            elif isinstance(r, dict):
                ids = list(r.get("input_ids", []))
            else:
                ids = list(r)
        except Exception:
            ids = None
        if not ids:
            # 폴백: 단순 chat 템플릿 (encode 는 리스트 반환)
            text = (f"<|im_start|>system\n{args.system}<|im_end|>\n"
                    f"<|im_start|>user\n{args.prompt}<|im_end|>\n"
                    f"<|im_start|>assistant\n")
            ids = tok.encode(text)
        input_ids = ids

    print(f"프롬프트 토큰: {len(input_ids)}  생성: {args.n}  "
          f"steps: {args.steps}  threads: {args.threads}", file=sys.stderr)
    tokens_str = ",".join(map(str, input_ids))

    # --- diffuse-cli 호출 ---
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = ":".join(_build_ld_path(args.cpp_bin))

    cmd = [args.cpp_bin, "-m", args.gguf, "--tokens", tokens_str,
           "-n", str(args.n), "-s", str(args.steps), "-t", str(args.threads),
           "--temp", str(args.temp), "--seed", str(args.seed),
           "--schedule", args.schedule, "--remasking", args.remasking,
           "--entropy-threshold", str(args.entropy_threshold)]
    if args.no_cache:
        cmd.append("--no-cache")
    if args.cache_refresh > 0:
        cmd += ["--cache-refresh", str(args.cache_refresh)]
    if args.cache_keep_active > 0:
        cmd += ["--cache-keep-active", str(args.cache_keep_active)]

    print("실행: " + " ".join(cmd[:6]) + " ...", file=sys.stderr)
    res = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if res.returncode != 0:
        print("diffuse-cli 실패:", file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        return res.returncode
    if res.stderr:
        print(res.stderr, file=sys.stderr, end="")

    out = res.stdout.strip()
    if not out:
        print("diffuse-cli 출력 없음", file=sys.stderr)
        return 1
    output_ids = [int(x) for x in out.split(",")]

    # --- 디코드 (마스크 토큰 제거) ---
    clean = [t for t in output_ids if t != args.mask_id]
    text = tok.decode(clean, skip_special_tokens=True)

    print(f"\n[생성 {len(output_ids)} 토큰, "
          f"{len(clean) if clean else 0} 비-마스크]:", file=sys.stderr)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
