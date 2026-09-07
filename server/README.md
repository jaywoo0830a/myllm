# myLLM — 베어메탈 서버 설치/운영 가이드

> 이 디렉토리의 스크립트는 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서 실행한다.
> 클라이언트(VS Code) 쪽 설정은 상위 폴더 `client/` 를 참고.

---

## 0) 사전 준비

서버에 이 레포를 받는다 (이 워크스페이스에서 push 한 뒤):

```bash
git clone <repo-url> myllm
cd myllm/server
```

환경설정 파일 생성:

```bash
cp config/env.example config/env
nano config/env        # HOST/PORT, HF_REPO, MODEL_FILE 등을 확인/조정
```

- 기본 포트 `8080`. 원격 VS Code 접속을 위해 `LLAMA_HOST=0.0.0.0` 로 LAN에 열림.
- GGUF (사용자 선택): `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` 의
  `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` (≈18.6GB). MoE — 토큰당 활성 ~3B, arch `qwen3moe`(llama.cpp 안정).
  - 다른 양자화(IQ4_XS/Q5_K_M 등)를 쓰려면 `env` 의 `HF_REPO`/`MODEL_FILE` 변경.

---

## 1) llama.cpp 빌드 (설치 전 최신 master 필수)

> **중요**: llama.cpp 가 최신 master 여야 `qwen3moe` 및 최신 기능 지원.
> 이 스크립트는 master 를 클론/업데이트하고 AVX-512 로 빌드한다.

```bash
bash scripts/01_setup_llamacpp.sh
```

빌드 후 버전/arch 로드 가능 여부는 스텝 3 스모크로 확인.

---

## 2) GGUF 모델 다운로드 (HF 토큰으로 속도/인증 개선 - 권장)

### (선택) HuggingFace Read 토큰 설정 — 인증 다운로드로 속도·안정성 개선

1. https://huggingface.co/settings/tokens 에서 **Read** 권한 토큰 생성.
2. 서버에서 설정 (입력이 화면/히스토리에 안 남음):

```bash
bash scripts/06_set_hf_token.sh     # 프롬프트에 토큰 붙여넣기
```

> 토큰은 `server/config/hf_token` 에 저장되며 **.gitignore 대상**(커밋/푸시 안 됨, 권한 600).
> 대신 `server/config/env` 의 `HF_TOKEN` 에 직접 넣어도 되고,
> `~/.cache/huggingface/token`(huggingface-cli 로그인) 도 자동 인식.

### (선택) 병렬 분할 다운로드 도구 (대용량일 때 체감 속도 향상)

```bash
sudo apt install -y aria2
# env 의 HF_DL_THREADS 를 4~8 로 설정하면 aria2c 로 분할 다운로드
```

### 모델 다운로드 실행

```bash
bash scripts/02_download_model.sh
```

`~/models/<MODEL_FILE>` 로 저장. 중단 시 재실행하면 **이어받기**됨.

---

## 3) 서버 실행 + 스모크 테스트 (일단 포그라운드로 확인)

```bash
bash scripts/03_run_server.sh
```

- 모델 로드에 수십 초~수 분 소요. 로드 후 `llama server listening on http://0.0.0.0:8080` 확인.
- **다른 터미널**에서:

```bash
bash scripts/test_server.sh
# 원격에서 테스트하려면:
LLAMA_HOST=<서버IP> bash scripts/test_server.sh
```

`pong` 응답이 오면 서버 정상.

---

## 4) 상시 데몬화 (systemd, 재부팅 자동 기동) + 방화벽

Ctrl+C 로 3번 서버를 끈 뒤:

```bash
bash scripts/05_install_systemd.sh
```

관리 명령:

```bash
systemctl status myllm-llama       # 상태
journalctl -u myllm-llama -f       # 실시간 로그
sudo systemctl restart myllm-llama # 재시작
sudo systemctl stop myllm-llama    # 중지
```

방화벽이 있으면 8080 개방 (예: ufw):

```bash
sudo ufw allow 8080/tcp
```

서버 IP 확인:

```bash
hostname -I
```

---

## 5) 클라이언트(VS Code) 연결

이 머신이 아닌 **클라이언트 컴퓨터의 VS Code** 에서 `Continue` 확장 설치 후,
`~/.continue/config.yaml` 를 `../../client/continue/config.yaml.example` 를 참고해 작성.
`<서버IP>` 를 위에서 확인한 서버 IP 로 교체.

자세한 내용은 저장소 루트의 `README.md` 및 `PLAN.md` 참고.

---

## 문제 해결

| 증상 | 대응 |
|------|------|
| 모델 로드 실패/arch 오류 | llama.cpp 가 오래된 버전 → `01_setup_llamacpp.sh` 재실행(master 갱신) |
| 응답에 장문 chain-of-thought | `env` 의 `NO_THINK=1`(미지원 버전이면 llama.cpp 최신화) |
| 클라이언트 연결 안 됨 | `test_server.sh` 로 서버 쪽 먼저, 서버 IP/방화벽/`apiBase`의 `/v1` 확인 |
| 느림 | CPU 8코어. MoE(활성~3B)라 보통 만족스러움. 그래도 느리면 `CTX_SIZE`/스레드(-t) 튜닝 |
