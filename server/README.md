# myLLM — 베어메탈 서버 설치/운영 가이드

> 이 디렉토리의 스크립트는 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서 실행한다.
> 여러 모델을 각자 프로파일(`config/models/<slug>.env`)로 동시에 띄운다.
> 클라이언트(VS Code) 쪽 설정은 상위 폴더 `client/` 를 참고.

기본 구성되는 모델 프로파일:
| slug | 모델 | GGUF 크기 | 포트 | 용도 |
|------|------|-----------|------|------|
| `deepseek-r1-32b` | DeepSeek-R1-Distill-Qwen-32B (unsloth) | ~19.9GB | 8081 | 메인 (무거운 reasoning, 느림) |
| `deepseek-1.5b` | DeepSeek-R1-Distill-Qwen-1.5B | ~1.0GB | 8080 | 경량 보조 (빠른 채팅) |

> 두 모델 모두 R1 distill = **항상 `<think>` 먼저 출력, 억제 불가**.
> 32B 메인은 9700X CPU에서 ~2.5-4 t/s 예상(대역폭 병목). 함께 돌면 1.5B 속도에도 영향.

---

## 0) 사전 준비

서버에 이 레포를 받고 공통 설정 + 모델 프로파일 활성화:

```bash
git clone <repo-url> myllm
cd myllm/server

# 공통(base)
cp config/env.example config/env
nano config/env        # LLAMA_HOST(0.0.0.0), 경로/토큰/스레드 등

# 사용할 모델 프로파일 활성화 (.env.example -> .env)
cp config/models/deepseek-r1-32b.env.example config/models/deepseek-r1-32b.env
cp config/models/deepseek-1.5b.env.example    config/models/deepseek-1.5b.env
nano config/models/deepseek-r1-32b.env        # 포트/스레드/ctx/양자화 조정
```

> 활성화된 모델 = `config/models/*.env` 에 존재하는 것. `run_all.sh` / `install_models.sh` 가
> 이 목록을 자동으로 쓴다. 더 추가하려면 `.gguf` 파일명만 같게 다른 slug 를 복사하면 된다.
> (모델별 HF_REPO/MODEL_FILE/LLAMA_PORT/THREADS/CTX_SIZE 등은 각 프로파일이 담당)

---

## 1) llama.cpp 빌드 (master)

```bash
bash scripts/01_setup_llamacpp.sh     # AVX-512, master 클론/업데이트+빌드
```

---

## 2) GGUF 다운로드 (HF 토큰 인증 권장)

HF Read 토큰(선택, 속도·인증 개선):
```bash
bash scripts/06_set_hf_token.sh
```
병렬 분할(선택): `sudo apt install -y aria2` 후 `config/env` 의 `HF_DL_THREADS=4~8`.

다운로드 (모델별):
```bash
bash scripts/download.sh deepseek-r1-32b # ~19.9GB
bash scripts/download.sh deepseek-1.5b   # ~1.0GB
```
`~/models/<파일>` 로 저장. 중단 시 재실행하면 이어받기.

---

## 3) 테스트 실행 (모두 백그라운드) + 스모크

```bash
bash scripts/run_all.sh            # config/models/*.env 전부 백그라운드 시작
```
- 각 모델 READY 로그를 확인 후(로드 몇 분) 다른 터미널에서:
```bash
bash scripts/test_server.sh deepseek-r1-32b      # or deepseek-1.5b
# 원격이면:
LLAMA_HOST=<서버IP> bash scripts/test_server.sh deepseek-r1-32b
```
모델별 alias 확인: `curl http://127.0.0.1:8081/v1/models`

테스트 종료/상태:
```bash
bash scripts/run_all.sh --stop
bash scripts/run_all.sh --status
```

---

## 4) 상시 데몬화 (systemd, 재부팅 자동) + 방화벽

3단계 데몬을 모두 종료한 뒤(중복 방지):
```bash
bash scripts/install_models.sh           # 활성 모델 각각 enable+start
# 특정 모델만: bash scripts/install_models.sh deepseek-r1-32b
```

관리 (템플릿 유닛 `myllm-llama@<slug>`):
```bash
systemctl status 'myllm-llama@*'
journalctl -u 'myllm-llama@deepseek-r1-32b' -f
sudo systemctl restart myllm-llama@deepseek-r1-32b
sudo systemctl stop myllm-llama@deepseek-1.5b

# 방화벽
sudo ufw allow 8080/tcp && sudo ufw allow 8081/tcp

# 서버 IP
hostname -I
```

---

## 5) 클라이언트(VS Code) 연결

클라이언트 컴퓨터의 VS Code 에서 `Continue` 확장 설치 후,
`~/.continue/config.yaml` 를 `client/continue/config.yaml.example` 를 참고해 작성:
- deepseek-r1-32b → `http://<서버IP>:8081/v1` (메인: chat)
- deepseek-1.5b → `http://<서버IP>:8080/v1` (보조: chat)

자세한 내용은 저장소 루트 `README.md` 및 `PLAN.md` 참고.

---

## 문제 해결

| 증상 | 대응 |
|------|------|
| 모델 로드 실패/arch 오류 | llama.cpp 구버전 → `01_setup_llamacpp.sh` 재실행(master) |
| 응답에 장문 chain-of-thought | 해당 모델 프로파일 `NO_THINK=1` → systemd 재시작 |
| 특정 포트 못 잡음 | `run_all.sh --status`, `ss -ltnp` 로 포트/프로세스 확인 |
| 두 모델 동시에 느림 | 8코어 분할이 원인. 프로파일 `THREADS` 조절(예: 14B=8, 1.5B=4 → 실제 필요 조정) |
| 클라이언트 연결 안 됨 | `test_server.sh` 로 서버 먼저, IP/방화벽/`apiBase`의 `/v1` 확인 |
