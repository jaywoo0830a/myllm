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
- GGUF 저장소 기본값은 `mradermacher/Qwen3.5-27B-GGUF` / `Qwen3.5-27B.Q4_K_M.gguf` (≈16.6GB).
  - 다른 저장소(예: `unsloth/Qwen3.5-27B-GGUF`)를 쓰려면 `env` 의 `HF_REPO`/`MODEL_FILE` 변경.

---

## 1) llama.cpp 빌드 (설치 전 최신 master 필수)

> **중요**: Qwen3.5 는 hybrid attention(arch `qwen35`)이라 **최신 llama.cpp** 에서만 로드된다.
> 이 스크립트는 master 를 클론/업데이트하고 AVX-512 로 빌드한다.

```bash
bash scripts/01_setup_llamacpp.sh
```

빌드 후 버전/arch 로드 가능 여부는 스텝 3 스모크로 확인.

---

## 2) GGUF 모델 다운로드

```bash
bash scripts/02_download_model.sh
```

`~/models/<MODEL_FILE>` 로 저장된다.

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
| 응답에 `<think>` 장문 코T | `env` 의 `NO_THINK=1` → systemd 재시작, `--no-think` 미지원 버전이면 llama.cpp 최신화 |
| 클라이언트 연결 안 됨 | `test_server.sh` 로 서버 쪽 먼저, 서버 IP/방화벽/`apiBase`의 `/v1` 확인 |
| 느림(3~6 tok/s) | 정상. CPU 8코어 + RAM 대역폭 병목. 컨텍스트를 더 줄이면 약간 나아짐(`CTX_SIZE`) |
