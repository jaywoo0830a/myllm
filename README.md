# myllm

**여러 로컬 모델**을 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서 `llama.cpp llama-server` 로
OpenAI 호환 API로 동시 서빙하고, 이 저장소(=클라이언트 머신)의 **VS Code Continue.dev** 가 그 API를 원격 호출하는 구축 프로젝트.

현재 구성된 모델 프로파일 (`server/config/models/`):
- **`qwen3-14b`** — Qwen3-14B (Q4_K_M, ~9.3GB) — 메인 (포트 **8081**)
- **`deepseek-1.5b`** — DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M, ~1.0GB) — 경량 보조 (포트 **8080**)

## 구조

```
myllm/
├── PLAN.md                      # 아키텍처/모델 팩트/단계
├── server/                      # ★ 베어메탈 서버에서 pull 해서 실행
│   ├── README.md                #   설치/운영 순서 (가장 먼저 읽기)
│   ├── config/
│   │   ├── env.example          #   공통(base) 설정 (host/경로/token)
│   │   └── models/              #   모델 프로파일 (slug 단위)
│   │       ├── deepseek-1.5b.env.example
│   │       └── qwen3-14b.env.example
│   ├── scripts/
│   │   ├── lib.sh               #   공통 헬퍼 (env 로드/토큰/경로)
│   │   ├── 01_setup_llamacpp.sh #   llama.cpp 빌드 (AVX-512, master)
│   │   ├── 06_set_hf_token.sh   #   HF Read 토큰 저장 (gitignore)
│   │   ├── download.sh <slug>   #   모델별 GGUF 다운로드(토큰/이어받기)
│   │   ├── run_one.sh <slug>    #   모델별 llama-server (테스트/수동)
│   │   ├── run_all.sh           #   모든 모델 백그라운드(테스트용)
│   │   ├── install_models.sh    #   모델별 systemd 템플릿 등록(상시화)
│   │   └── test_server.sh <slug>#   /v1 스모크 테스트
│   └── systemd/myllm-llama@.service   # systemd 템플릿(@모델slug)
└── client/                      # 클라이언트(VS Code) 설정 템플릿
    └── continue/
        └── config.yaml.example  #   Continue.dev ~/.continue/config.yaml 용
```

## 연결 구조 (2 모델 병렬)

```
[클라이언트 머신 = 이 저장소]
  VS Code &#8594; Continue.dev
      │  OpenAI 호환 /v1
      ├─ http://<서버IP>:8080/v1   (deepseek-1.5b, 경량 보조)
      └─ http://<서버IP>:8081/v1   (qwen3-14b, 메인)
[베어메탈 서버] llama-server x2 (각 프로파일 1개 프로세스, CPU 스레드 분할)
```

## 빠른 시작 (서버, 베어메탈)

```bash
git clone <repo-url> myllm && cd myllm/server

# 1) 공통 설정 + 모델 프로파일 활성화
cp config/env.example config/env
cp config/models/qwen3-14b.env.example     config/models/qwen3-14b.env
cp config/models/deepseek-1.5b.env.example config/models/deepseek-1.5b.env
#    (포트/스레드/ctx 등 편집 가능)

# 2) 빌드 + 토큰 + 다운로드
bash scripts/01_setup_llamacpp.sh          # llama.cpp 빌드
bash scripts/06_set_hf_token.sh            # (선택) HF Read 토큰
bash scripts/download.sh qwen3-14b         # ~9.3GB
bash scripts/download.sh deepseek-1.5b     # ~1.0GB

# 3) 테스트 실행 (모두 백그라운드)
bash scripts/run_all.sh
bash scripts/test_server.sh qwen3-14b      # pong 확인
bash scripts/test_server.sh deepseek-1.5b
bash scripts/run_all.sh --stop

# 4) 상시화 (systemd, 재부팅 자동)
bash scripts/install_models.sh             # config/models/*.env 전부
sudo ufw allow 8080/tcp && sudo ufw allow 8081/tcp
hostname -I                                # 서버 IP 기록
```

자세한 단계는 `server/README.md` 참고.

**클라이언트(이 머신의 VS Code)에서:**
1. Continue 확장 설치
2. `cp client/continue/config.yaml.example ~/.continue/config.yaml`
3. `<서버IP>` 를 실제 IP로 교체, 각 모델 `apiBase`(포트 8080/8081) 확인.
   모델 id 는 `curl http://<서버IP>:<포트>/v1/models` 로 확인해 `model:` 값과 일치.
4. Continue 패널에서 메인(qwen3-14b)은 채팅/편집, 보조(deepseek-1.5b)는 빠른 채팅 등으로 선택 사용

## 참고
- GPU 없이 CPU 8코어로 동시 2모델:
  - `qwen3-14b`(메인, ~9.3GB, 8스레드/포트8081) — 무거운 코딩/편집/추론
  - `deepseek-1.5b`(보조, ~1.0GB, 4스레드/포트8080) — 빠른 채팅/요약
- 8코어를 스레드로 분할하므로 동시 요청 시 성능 분산 — 프로파일의 `THREADS` 로 조절.
- GGUF:
  - `Qwen/Qwen3-14B-GGUF` → `Qwen3-14B-Q4_K_M.gguf`
  - `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF` → `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf`
- 상세 모델 팩트·리스크는 `PLAN.md` 를 볼 것.
