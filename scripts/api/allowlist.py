"""화이트리스트(allowlist) 정의 — 제3자가 실행 가능한 셸 스크립트만 허가.

보안 원칙
---------
- "임의 명령 실행"이 아니라 "허용된 스크립트의 호출"만 노출한다.
- 각 액션(action)은 실행할 스크립트 경로와 허용 인자를 가진다.
- 인자는 화이트리스트에 정의된 model slug(예: parser, worker1, ...)만 통과시킨다.
- shell=True / f-string 셸 조합을 쓰지 않고, subprocess 에 리스트로 전달한다.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

# 저장소 루 기준 server/scripts 디렉터리
#   scripts/api/allowlist.py  →  .. 는 scripts  →  ../server/scripts
_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.environ.get(
    "MYLLM_SCRIPTS_DIR",
    os.path.join(_REPO, "server", "scripts"),
)

# 허용 가능한 모델 slug (config/models/<slug>.env 존재분 기준)
ALLOWED_SLUGS = {
    "parser", "worker1", "worker2", "worker3", "worker4",
    "coder1", "coder2", "coder3", "coder4",
    "reasoner", "setter", "judge",
}

# 14B 상호배타 대상
HEAVY_SLUGS = {"setter", "judge"}


@dataclass
class Action:
    """실행 가능한 액션 하나. arg: 0 또는 1개."""
    name: str
    script: str               # BASE 기준 상대 경로
    needs_arg: bool = False   # 모델 slug 인자 필요 여부
    arg_choices: set = field(default_factory=set)  # 비면 ALLOWED_SLUGS 허용


def _p(name: str) -> str:
    return os.path.join(BASE, name)


ACTIONS: dict[str, Action] = {
    "up":             Action("up",  "up.sh", needs_arg=True),
    "down":           Action("down", "down.sh", needs_arg=True),
    "start_all":      Action("start_all", "start_all.sh"),
    "start_heavy":    Action("start_heavy", "start_heavy.sh", needs_arg=True, arg_choices=HEAVY_SLUGS),
    "status":         Action("status", "status_report.sh", arg_choices=set()),
    "restart":        Action("restart", "restart.sh", needs_arg=True),
    "log":            Action("log", "log.sh", needs_arg=True),
}


def resolve(action: str, arg: str | None) -> tuple[list[str], str]:
    """(argv 리스트, 사람이 읽을 설명). 잘못됐으면 ValueError."""
    a = ACTIONS.get(action)
    if a is None:
        raise ValueError(f"unknown action: {action!r}")
    script_abs = _p(a.script)
    if not os.path.isfile(script_abs):
        raise ValueError(f"script not found: {script_abs}")

    argv = ["bash", script_abs]
    # status 는 컨테이너/원격 실행이므로 실제 프로세스를 못 본다.
    # → --remote (저장소 설정 기준) + 출력을 /tmp 로 보내 조회 목적에 맞춘다.
    #   (루 STATUS.md 를 읽기전용 컨테이너에서 덮어쓰지 않도록)
    if a.name == "status":
        argv += ["-o", "/tmp/myllm_STATUS.md", "--remote"]
    if a.needs_arg:
        if arg is None:
            raise ValueError(f"action {action!r} requires 'arg' (model slug)")
        choices = a.arg_choices or ALLOWED_SLUGS
        if arg not in choices:
            raise ValueError(f"arg {arg!r} not allowed for {action!r}")
        argv.append(arg)
    return argv, a.name + (f" {arg}" if a.needs_arg else "")