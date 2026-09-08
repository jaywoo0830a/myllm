#!/usr/bin/env python3
"""diffuse_server.py — diffuse-cpp(Dream) 를 OpenAI 호환 HTTP 서버로 노출

diffuse-cpp(diffuse-cli) 는 llama-server 같은 내장 서버가 없어 단일 호출이다.
GGUF 로드가 ~1초 이내(diffuse-cli 스모크 실측이라 상시 띄워도 재로드 부담 미미)므로,
요청이 올 때마다 diffuse-cli 를 subprocess 로 1회 실행해 생성한다.

노출 API(llama-server/openai 호환 최소):
  POST /v1/chat/completions
      body: { "model":"...", "messages":[{"role":"system"|"user"|"assistant","content":...}],
              "temperature":0, "max_tokens":256 }
      → OpenAI chat.completion JSON
  GET  /v1/models        → 사용 모델 정보
  GET  /health           → liveness

주의: diffusion 은 autoregressive 와 달리 "전체 토큰 병렬 정제"라
      max_tokens 는 diffuse-cli 의 `-n`(생성 청크) 과 `-s`(diffusion step)로 매핑된다.
      단순 질문은 entropy_exit 로 조기종료 → 체감 빠름.

상시 구동(systemd 등)시 이 파일을 venv-diffuse 파이썬으로 실행한다:
  /home/ubuntu/venv-diffuse/bin/python diffuse_server.py \
      --gguf /home/ubuntu/models/diffuse/dream-7b-q4km.gguf \
      --tokenizer /home/ubuntu/models/dream-tokenizer \
      --cpp-bin /home/ubuntu/diffuse-cpp/diffuse-cli \
      --port 8082
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


# ---- diffuse-cli 실행 공통(래퍼 diffuse_generate.py 와 동일 계약) ----
DEFAULT_MASK_ID = 151666  # Dream GGUF mask_token (스모크 확인)


def build_cmd(cpp_bin, gguf, tokens, *, n, steps, threads, temp=0.0, seed=42,
              schedule="cosine", remasking="entropy_exit", ent_thresh=1.5) -> list[str]:
    cmd = [cpp_bin, "-m", gguf, "--tokens", tokens,
           "-n", str(n), "-s", str(steps), "-t", str(threads),
           "--temp", str(temp), "--seed", str(seed),
           "--schedule", schedule, "--remasking", remasking,
           "--entropy-threshold", str(ent_thresh)]
    return cmd


def build_ld_path(cpp_bin: str) -> str:
    exe = Path(cpp_bin)
    if exe.is_symlink():
        exe = exe.resolve()
    parts = [str(exe.parent), str(exe.parent / "ggml" / "src")]
    if "LD_LIBRARY_PATH" in os.environ:
        parts.append(os.environ["LD_LIBRARY_PATH"])
    return ":".join(parts)


# ---- 토크나이저 로드(전역 1회 — 서버 수명 동안 재사용) ----
_tokenizer = None

def _get_tokenizer(tok_dir):
    global _tokenizer
    if _tokenizer is None:
        from transformers import AutoTokenizer
        _tokenizer = AutoTokenizer.from_pretrained(tok_dir, trust_remote_code=True)
    return _tokenizer


def tokenize_chat(tok, messages: list[dict]) -> list[int]:
    """OpenAI messages → diffuse-cli 토큰 ID 리스트.

    diffusion 은 "전체 문단을 병렬 정제"하므로 대화 히스토리는 시스템 뒤에
    이어붙여 컨텍스트로 넣는다(autoregressive 와 동일한 전체 문맥 주입).
    """
    # 시스템 + 전체 히스토리(user/assistant)를 순서대로 유지 후 마지막 user 가 프롬프트.
    sys_p = next((m["content"] for m in messages if m.get("role") == "system"), None)
    chat = []
    if sys_p:
        chat.append({"role": "system", "content": sys_p})
    for m in messages:
        if m.get("role") in ("user", "assistant") and m.get("content"):
            chat.append({"role": m["role"], "content": m["content"]})
    if not chat:
        chat = [{"role": "user", "content": messages[-1].get("content", "")}]
    try:
        r = tok.apply_chat_template(chat, add_generation_prompt=True, tokenize=True)
        if hasattr(r, "input_ids"):
            return list(r.input_ids)
        if isinstance(r, dict):
            return list(r.get("input_ids", []))
        return list(r)
    except Exception:
        user_p = (([m for m in chat if m["role"] == "user"] or [chat[-1]])[-1]).get("content", "")
        text = (f"<|im_start|>system\n{sys_p or 'You are a helpful assistant.'}<|im_end|>\n"
                f"<|im_start|>user\n{user_p}<|im_end|>\n<|im_start|>assistant\n")
        return tok.encode(text)


def run_diffuse(cpp_bin, gguf, tokens, *, n, steps, threads, temp=0.0):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = build_ld_path(cpp_bin)
    cmd = build_cmd(cpp_bin, gguf, ",".join(map(str, tokens)),
                    n=n, steps=steps, threads=threads, temp=temp)
    # stderr만 화면에, stdout 은 토큰
    res = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if res.returncode != 0:
        raise RuntimeError(f"diffuse-cli 실패({res.returncode}): {res.stderr[-300:]}")
    out = res.stdout.strip()
    return ([int(x) for x in out.split(",")] if out else []), res.stderr


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # 조용히
        pass

    def _send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/v1/models", "/models"):
            self._send_json({"object": "list", "data": [{
                "id": "dream-v0-7b", "object": "model",
                "created": 0, "owned_by": "diffuse-cpp"}]})
        elif self.path in ("/health", "/"):
            self._send_json({"status": "ok", "model": "Dream-v0-7B (diffusion)"})
        else:
            self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path not in ("/v1/chat/completions", "/chat/completions"):
            self._send_json({"error": "not found"}, 404); return
        try:
            ln = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(ln) or b"{}")
        except Exception as e:
            self._send_json({"error": f"bad request: {e}"}, 400); return

        messages = req.get("messages", [])
        temperature = float(req.get("temperature", 0.0) or 0.0)
        max_tokens = int(req.get("max_tokens", 256) or 256)
        if not messages:
            self._send_json({"error": "messages required"}, 400); return

        try:
            tok = _get_tokenizer(self.server.tok_dir)
            tokens = tokenize_chat(tok, messages)
        except Exception as e:
            self._send_json({"error": f"tokenize: {e}"}, 500); return

        # diffusion: 생성 길이는 -n(청크 크기). entropy_exit 로 필요만큼만.
        n = max(16, min(max_tokens, self.server.max_gen))
        steps = self.server.steps
        threads = self.server.threads
        gguf = self.server.gguf
        cpp = self.server.cpp_bin

        try:
            out_ids, _ = run_diffuse(cpp, gguf, tokens, n=n, steps=steps,
                                     threads=threads, temp=temperature)
        except Exception as e:
            self._send_json({"error": f"inference: {e}"}, 500); return

        # diffusion 은 스케줄러가 각 위치의 최종 토큰을 순서대로 내므로 out_ids 전체가
        # 실제 어휘 토큰이다. 특수토큰(eos/pad 등)만 제외하고 디코드.
        try:
            content = tok.decode(out_ids, skip_special_tokens=True)
        except Exception as e:
            self._send_json({"error": f"decode: {e}"}, 500); return

        resp = {
            "id": "chatcmpl-diffuse", "object": "chat.completion",
            "created": 0, "model": "dream-v0-7b",
            "choices": [{"index": 0,
                         "message": {"role": "assistant", "content": content.strip()},
                         "finish_reason": "stop"}],
            "usage": {"prompt_tokens": len(tokens),
                      "completion_tokens": len(out_ids),
                      "total_tokens": len(tokens) + len(out_ids)},
        }
        self._send_json(resp)


class DiffuseServer(ThreadingHTTPServer):
    def __init__(self, addr, handler, *, gguf, tok_dir, cpp_bin, mask_id,
                 max_gen, steps, threads):
        super().__init__(addr, handler)
        self.gguf, self.tok_dir = gguf, tok_dir
        self.cpp_bin, self.mask_id = cpp_bin, mask_id
        self.max_gen, self.steps, self.threads = max_gen, steps, threads


def main():
    ap = argparse.ArgumentParser(description="diffuse-cpp(Dream) OpenAI 호환 서버")
    ap.add_argument("--gguf", required=True)
    ap.add_argument("--tokenizer", required=True)
    ap.add_argument("--cpp-bin", default="diffuse-cli")
    ap.add_argument("--port", type=int, default=8082)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--steps", "-s", type=int, default=16,
                    help="diffusion step (entropy_exit 로 조기종료됨)")
    ap.add_argument("--threads", "-t", type=int, default=8)
    ap.add_argument("--max-gen", type=int, default=512, help="-n 상한")
    args = ap.parse_args()

    # 로드 체크
    if not Path(args.gguf).exists():
        print(f"[!!] GGUF 없음: {args.gguf}", file=sys.stderr); sys.exit(1)
    tok = _get_tokenizer(args.tokenizer)  # 시작 시 1회 로드 검증(오류 조기 노출)
    _tokenizer = tok
    print(f"토크나이저 로드 OK: {type(tok).__name__}", file=sys.stderr)

    srv = DiffuseServer((args.host, args.port), Handler,
                        gguf=args.gguf, tok_dir=args.tokenizer,
                        cpp_bin=args.cpp_bin, mask_id=DEFAULT_MASK_ID,
                        max_gen=args.max_gen, steps=args.steps,
                        threads=args.threads)
    print(f"diffuse(Dream) 서버 시작: http://{args.host}:{args.port}/v1/chat/completions",
          file=sys.stderr, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
