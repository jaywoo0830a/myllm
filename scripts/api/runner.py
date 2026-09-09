"""셸 스크립트 실행기 — 허용 목록(allowlist)만 실행 가능.

- subprocess.run 에 argv 리스트를 그대로 전달 (shell=False 가 기본, 주입 방지).
- 타임아웃으로 무한 대기 방지.
- stdout/stderr 를 캡처해 호출자에게 돌려준다.
"""

from __future__ import annotations

import shutil
import subprocess
import time
from dataclasses import dataclass


@dataclass
class RunResult:
    ok: bool
    returncode: int
    stdout: str
    stderr: str
    elapsed_s: float
    timed_out: bool = False


DEFAULT_TIMEOUT = int(__import__("os").environ.get("MYLLM_CMD_TIMEOUT", "180"))


def run_argv(argv: list[str], timeout: int | None = None) -> RunResult:
    """argv 를 bash 로 실행하고 결과를 캡처한다. (shell 은 사용하지 않음)

    스크립트는 shebang 이 아니라 명시적으로 bash 를 통해 실행하므로,
    bash 가 반드시 필요하다. (Docker 유틸리티 베이스에 bash 포함)
    """
    if shutil.which("bash") is None:
        return RunResult(False, 127, "", "bash not found in PATH", 0.0)

    timeout = timeout or DEFAULT_TIMEOUT
    t0 = time.monotonic()
    timed_out = False
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        returncode = proc.returncode
        stdout, stderr = proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as exc:  # type: ignore[assignment]
        timed_out = True
        returncode = -1
        stdout = exc.stdout or ""
        stderr = (exc.stderr or "") + f"\n[TIMEOUT after {timeout}s]"
    except OSError as exc:  # e.g. script missing / no exec
        return RunResult(False, 127, "", f"OSError: {exc}", time.monotonic() - t0)

    elapsed = time.monotonic() - t0
    return RunResult(returncode == 0, returncode, stdout or "", stderr or "", elapsed, timed_out)