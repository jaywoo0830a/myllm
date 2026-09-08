# myllm

**DeepSeek-R1-Distill-Qwen-14B** 를 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서 `llama.cpp llama-server` 로
OpenAI 호환 API로 서빙하고, 이 저장소(=클라이언트 머신)의 **VS Code Continue.dev** 가 그 API를 원격 호출하는 구축 프로젝트.

운영 모델 프로파일 (`server/config/models/`):
- **`deepseek-r1-14b`** — DeepSeek-R1-Distill-Qwen-14B (Q4_K_M, ~8.9GB) — 포트 **8081** (유일 모델)

> 14B 는 R1 distill = **항상 `<think>`(reasoning) 먼저 출력**하며 억제가 불가합니다.

## 구조

```
myllm/
├── PLAN.md                      # 아키텍처/모델 팩트/단계
├── server/                      # ★ 베어메탈 서버에서 pull 해서 실행
│   ├── README.md                #   설치/운영 순서 (가장 먼저 읽기)
│   ├── config/
│   │   ├── env.example          #   공통(base) 설정 (host/경로/token)
│   │   └── models/              #   모델 프로파일 (slug 단위)
│   │       └── deepseek-r1-14b.env.example
│   ├── scripts/
│   │   ├── lib.sh               #   공통 헬퍼 (env 로드/토큰/경로)
│   │   ├── setup_llamacpp.sh    #   llama.cpp 빌드 (AVX-512, master)
│   │   ├── set_hf_token.sh      #   HF Read 토큰 저장 (gitignore)
│   │   ├── download.sh <slug>   #   GGUF 다운로드(토큰/이어받기)
│   │   ├── run_one.sh <slug>    #   llama-server (테스트/수동)
│   │   ├── run_all.sh           #   활성 모델 백그라운드(테스트용)
│   │   ├── install_models.sh    #   systemd 템플릿 등록(상시화)
│   │   ├── overnight_gen.sh     #   밤샘 장문 생성(파일 저장)
│   │   └── test_server.sh <slug>#   /v1 스모크 테스트
│   └── systemd/myllm-llama@.service   # systemd 템플릿(@모델slug)
└── client/                      # 클라이언트(VS Code) 설정 템플릿
    └── continue/
        └── config.yaml.example  #   Continue.dev ~/.continue/config.yaml 용
```

## 연결 구조 (단일 모델)

```
[클라이언트 머신 = 이 저장소]
  VS Code &#8594; Continue.dev
      │  OpenAI 호환 /v1
      └─ http://<서버IP>:8081/v1   (deepseek-r1-14b)
[베어메탈 서버] llama-server x1 (deepseek-r1-14b, full 8 코어)
```

## 빠른 시작 (서버, 베어메탈)

```bash
git clone <repo-url> myllm && cd myllm/server

# 1) 공통 설정 + 모델 프로파일 활성화
cp config/env.example config/env
cp config/models/deepseek-r1-14b.env.example config/models/deepseek-r1-14b.env
#    (포트/스레드/ctx/KV_CACHE 등 편집 가능)

# 2) 빌드 + 토큰 + 다운로드
bash scripts/setup_llamacpp.sh          # llama.cpp 빌드
bash scripts/set_hf_token.sh            # (선택) HF Read 토큰
bash scripts/download.sh deepseek-r1-14b   # ~8.9GB

# 3) 테스트 실행 (백그라운드)
bash scripts/run_all.sh
bash scripts/test_server.sh deepseek-r1-14b   # pong 확인 (로드 수 분)
bash scripts/run_all.sh --stop

# 4) 상시화 (systemd, 재부팅 자동)
bash scripts/install_models.sh             # deepseek-r1-14b enable+start
sudo ufw allow 8081/tcp
hostname -I                                # 서버 IP 기록
```

자세한 단계는 `server/README.md` 참고.

**클라이언트(이 머신의 VS Code)에서:**
1. Continue 확장 설치
2. `cp client/continue/config.yaml.example ~/.continue/config.yaml`
3. `<서버IP>` 를 실제 IP로 교체.
   모델 id 는 `curl http://<서버IP>:8081/v1/models` 로 확인해 `model:` 값과 일치.
4. Continue 패널에서 deepseek-r1-14b 를 선택해 사용
   (R1 reasoning — 답변 전 `<think>`가 길게 나올 수 있음)

## 참고
- CPU 8코어 단일 모델(14B). 전 코어/대역폭 전용.
  - `deepseek-r1-14b`(~8.9GB, 8스레드/포트8081) — R1 reasoning 모델 (**32B 대비 약 2배 빠른 ~6-7 t/s 예상**, 그래도 CoT 길면 느림)
- GGUF: `unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF` → `DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf`
- 속도 튜닝: `KV_CACHE=q8_0`(이미 프로파일 기본). 긴 문서는 `overnight_gen.sh` 로 백그라운드 생성.
- 상세 모델 팩트·리스크는 `PLAN.md` 를 볼 것.
