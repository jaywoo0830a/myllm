"""myLLM Script Runner API — 제3자 내부 서비스가 허용된 셸 스크립트를 실행하기 위한 HTTP 인터페이스.

엔드포인트
----------
- GET  /                          : 기본 환영 메시지 + 스크립트 출력
- GET  /openapi.json              : OpenAPI 문서 (FastAPI 기본)
- POST /v1/run                    : 화이트리스트 액션 실행 (본문 예시는 아래 참고)
- GET  /v1/allowlist              : 실행 가능한 액션/슬러그 목록
- GET  /health                    : 헬스체크

보안
----
- 화이트리스트(allowlist.py)에 없는 액션이나 slug 는 400 으로 거부.
- shell=True 미사용(subprocess argv 리스트 전달), 파라미터 주입 차단.
- 인증은 EXTERNAL_TOKEN(옵션)이 설정되면 `Authorization: Bearer <token>` 요구.

추가 배포 참고
--------------
- 컨테이너는 저장소를 bind-mount 하여 server/scripts/*.sh 를 직접 실행한다.
- 실제 서버 프로세스 상태를 보려면 컨테이너가 아닌 호스트에서 status_report.sh 를
  실행하는 것이 정확하다. (runner 는 --remote 로 동작)
"""

from __future__ import annotations

import os

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from . import allowlist, runner

APP_VERSION = "1.0.0"
TOKEN = os.environ.get("EXTERNAL_TOKEN", "").strip()


def _require_auth(authorization: str | None) -> None:
    if not TOKEN:
        return
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing Bearer token")
    if authorization.removeprefix("Bearer ").strip() != TOKEN:
        raise HTTPException(status_code=401, detail="invalid token")


class RunRequest(BaseModel):
    action: str = Field(..., description="allowlist 액션 이름: up|down|start_all|start_heavy|status|restart|log")
    arg: str | None = Field(None, description="모델 slug (예: parser, worker1, setter, judge)")


app = FastAPI(title="myLLM Script Runner API", version=APP_VERSION)


@app.get("/", response_class=PlainTextResponse)
def root():
    return (
        "myLLM Script Runner API\n"
        "POST /v1/run   to execute an allowlisted script\n"
        "GET  /v1/allowlist  to list allowed actions\n"
        "GET  /health   for health check\n"
    )


@app.get("/health")
def health():
    import shutil

    return {
        "ok": True,
        "version": APP_VERSION,
        "bash_available": shutil.which("bash") is not None,
        "scripts_dir": os.environ.get("MYLLM_SCRIPTS_DIR", allowlist.BASE),
    }


@app.get("/v1/allowlist")
def get_allowlist(authorization: str | None = Header(default=None)):
    _require_auth(authorization)
    return {
        "actions": {name: (a.needs_arg, sorted(a.arg_choices or allowlist.ALLOWED_SLUGS)) for name, a in allowlist.ACTIONS.items()},
        "slugs": sorted(allowlist.ALLOWED_SLUGS),
        "heavy_slugs": sorted(allowlist.HEAVY_SLUGS),
    }


@app.post("/v1/run")
def run_action(req: RunRequest, authorization: str | None = Header(default=None)):
    _require_auth(authorization)
    try:
        argv, label = allowlist.resolve(req.action, req.arg)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    result = runner.run_argv(argv)
    return {
        "action": label,
        "ok": result.ok,
        "returncode": result.returncode,
        "elapsed_s": round(result.elapsed_s, 3),
        "timed_out": result.timed_out,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


# uvicorn --  직접 실행 지원 (python -m scripts.api.app)
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("API_PORT", "8000"))
    uvicorn.run("scripts.api.app:app", host="0.0.0.0", port=port, reload=False)