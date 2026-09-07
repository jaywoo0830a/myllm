# myllm

**LiquidAI LFM2.5-1.2B-Instruct(Q4_K_M, 1.2B)** 를 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서
`llama.cpp llama-server` 로 OpenAI 호환 API 서빙하고, 이 저장소(=클라이언트 머신)의 **VS Code Continue.dev** 가 그 API를 원격 호출하는 구축 프로젝트.

## 구조

```
myllm/
├── PLAN.md                      # 아키텍처/모델 팩트/단계 총정리
├── server/                      # ★ 베어메탈 서버에서 pull 해서 실행
│   ├── README.md                #   설치/운영 순서 안내 (가장 먼저 읽기)
│   ├── config/env.example       #   환경설정 (포트/모델/추론 파라미터)
│   ├── scripts/
│   │   ├── 01_setup_llamacpp.sh #   llama.cpp 빌드 (AVX-512, 최신 master)
│   │   ├── 02_download_model.sh #   GGUF 다운로드 (HF토큰/이어받기/병렬)
│   │   ├── 03_run_server.sh     #   llama-server 실행(테스트/수동)
│   │   ├── 05_install_systemd.sh#   systemd 상시 데몬 등록
│   │   ├── 06_set_hf_token.sh   #   HF Read 토큰 저장 (gitignore)
│   │   └── test_server.sh       #   /v1 스모크 테스트(curl)
│   └── systemd/myllm-llama.service
└── client/                      # 클라이언트(VS Code) 설정 템플릿
    └── continue/
        └── config.yaml.example  #   Continue.dev ~/.continue/config.yaml 용
```

## 연결 구조

```
[클라이언트 머신 = 이 저장소]
  VS Code &#8594; Continue.dev
      │  OpenAI 호환 /v1/chat/completions   (provider: openai)
      ▼  http://<서버IP>:8080/v1
[베어메탈 서버] llama-server &#8592; LFM2.5-1.2B-Instruct-Q4_K_M.gguf (~0.7GB, RAM 로드, CPU, 고속)
```

## 빠른 시작

**서버(베어메탈)에서:**
```bash
git clone <repo-url> myllm && cd myllm/server
cp config/env.example config/env   # 편집(포트/모델 등)
bash scripts/01_setup_llamacpp.sh  # llama.cpp 빌드
bash scripts/06_set_hf_token.sh    # (선택) HF Read 토큰 -> 인증 다운로드
bash scripts/02_download_model.sh  # GGUF 다운로드 (token 사용, 이어받기)
bash scripts/03_run_server.sh      # 1차 실행
#  다른 터미널:
bash scripts/test_server.sh        # pong 확인
#  Ctrl+C 후 상시화:
bash scripts/05_install_systemd.sh
sudo ufw allow 8080/tcp
hostname -I                        # 서버 IP 기록
```

자세한 단계는 `server/README.md` 참고.

**클라이언트(이 머신의 VS Code)에서:**
1. Continue 확장 설치
2. `cp client/continue/config.yaml.example ~/.continue/config.yaml`
3. `<서버IP>`를 실제 IP로 교체, 모델 id는 `curl http://<서버IP>:8080/v1/models` 로 확인해 맞춤
4. Continue 패널에서 채팅/편집 사용

## 참고
- 1.2B(≈0.7GB) 소형 고속 모델 — 9700X CPU 8코어에서 **매우 빠른 응답** 예상(실측 필요).
- GGUF 출처(사용자 선택): `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` — `LFM2.5-1.2B-Instruct-Q4_K_M.gguf`.
- 상세 모델 팩트·리스크는 `PLAN.md` 를 볼 것.
