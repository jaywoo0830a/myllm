# myLLM - Bare-metal server setup guide

The scripts in this directory start **any** model defined in `server/config/models/*.env` using `llama.cpp`'s `llama-server`. Each model runs on its own port and can be started independently.

> CPU(메모리 대역폭 결합) 환경이므로 **역할당 대표 1개만** 띄우는 것을 원칙으로 한다.
> 자세한 이유는 상위 `MODEL-ANALYSIS.md`(§1) 참조.

## Prerequisites

- Ubuntu 22.04 or later (AMD 9700X: 8C/16T, Zen5)
- 64 GB RAM (CPU-only)
- `git`, `bash`, `curl`, `aria2` (optional for parallel download)

## Setup steps

```bash
git clone <repo-url> myllm && cd myllm/server

# 1) 하나의 명령으로 config/env + 모델 env 를 .example 로부터 생성
bash scripts/init.sh parser

# 2) Build llama-cpp server
bash scripts/setup_llamacpp.sh          # -march=native(Zen5) + AVX-512 로 빌드

# 3) 모델 GGUF 다운로드 (slug: parser / worker1 / coder1 / reasoner / setter / judge)
bash scripts/download.sh parser
#    NOTE: reasoner(DeepSeek-R1-Distill-Qwen-7B) 는 unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF
#          (env 의 HF_REPO 참조) 에서 받을 수 있다.

# 4) 모델 서버 기동 (단일)
bash scripts/up.sh parser
```

> `init.sh` 는 `.env.example` 이 있는 모델을 자동으로 `.env` 로 만들어 주므로
> 각 모델을 일일이 `cp` 하지 않아도 된다.

## Helper scripts (tuned)

| 스크립트 | 용도 |
|---|---|
| `init.sh` | config/env + 모델 env 자동 생성, 디렉터리 준비 |
| `up.sh <slug>` | 단일 모델 서버를 background 로 기동 |
| `down.sh <slug>` | 단일 모델 서버 종료 |
| `down_all.sh` | 실행 중인 모든 llama-server 종료 |
| `start_all.sh` | **상시 세트(parser + worker1 + coder1)** 기동 |
| `start_heavy.sh setter\|judge` | 14B 를 단독(on-demand, 상호배타) 기동 |
| `status_report.sh` | 현재 상태를 `STATUS.md` 로 스냅샷 생성 |
| `log.sh <slug>` | 로그 조회 |
| `restart.sh <slug>` | 재시작 |

**KV 캐시 양자화:** `config/models/*.env` 의 `KV_CACHE=q8_0` 가
`llama_serve_generic.sh` 에서 `--cache-type-k q8_0 --cache-type-v q8_0` 로 반영된다.
(llama.cpp build 10858+ 는 옛 통합 `--cache-type "k:...,v:..."` 플래그가 제거됨)

> **주의:** `llama_serve_generic.sh` 는 `up.sh` 가 호출하는 **내부 헬퍼** 이므로 직접 실행하지 않는다.
> 직접 실행 시 사용법 안내 후 종료된다.

## 14B 상호배타 (on-demand)

Setter(8091) 와 Judge(8092) 는 14B 라 동시에 올리지 않는다 (메모리 원칙):

```bash
bash scripts/start_heavy.sh setter    # 문제 생성 전용
bash scripts/start_heavy.sh judge     # 검증 전용 (setter 와 배타)
bash scripts/down.sh judge            # 내리고 setter 를 다시 올린다
```

## Systemd (선택)

호스트에서 모델 프로세스를 직접 관리하려면 Script Runner API 를 systemd 로 띄울 수 있다:

```bash
sudo cp scripts/api/myllm-api.service /etc/systemd/system/
# {{SCRIPT_DIR}} 를 실제 경로로 치환 후:
sudo systemctl daemon-reload && sudo systemctl enable --now myllm-api
```

상세 배포 절차는 `scripts/api/DEPLOY.md` 참조.

## Firewall

모델 포트(8081-8092) 와 API 포트(18080) 를 열 필요가 있으면:

```bash
sudo ufw allow 8081:8092/tcp
sudo ufw allow 18080/tcp
```

## Performance tuning

빌드 플래그, 스레드, KV 캐시 설정, 벤치마크는 `server/scripts/performance_tuning.md` 참조.
자원 예산과 수학적 근거는 `MODEL-ANALYSIS.md` 참조.

## Client side

상위 `README.md` 의 클라이언트 구성 및 `scripts/api/README.md` 의 Script Runner API 사용법 참조.
