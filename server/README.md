# myLLM — 베어메탈 서버 설치/운영 가이드

> 이 디렉토리의 스크립트는 **별도 베어메탈 서버**(9700X · 64GB · Ubuntu)에서 실행한다.
> 모델 프로파일(`config/models/<slug>.env`)을 띄워 OpenAI 호환 API 로 서빙.
> 클라이언트(VS Code) 쪽 설정은 상위 폴더 `client/` 를 참고.

운영하는 모델 프로파일 (현재 단일):
| slug | 모델 | GGUF 크기 | 포트 |
|------|------|-----------|------|
| `deepseek-r1-14b` | DeepSeek-R1-Distill-Qwen-14B (unsloth) | ~8.9GB | 8081 |

> 14B 는 R1 distill = **항상 `<think>` 먼저 출력, 억제 불가**.
> 9700X CPU에서 ~6-7 t/s 예상 (32B 실측 2 t/s 의 약 2배). 메인/유일 모델.

---

## 0) 사전 준비

서버에 이 레포를 받고 공통 설정 + 모델 프로파일 활성화:

```bash
git clone <repo-url> myllm
cd myllm/server

# 공통(base)
cp config/env.example config/env
nano config/env        # LLAMA_HOST(0.0.0.0), 경로/토큰/스레드 등

# 모델 프로파일 활성화 (.env.example -> .env)
cp config/models/deepseek-r1-14b.env.example config/models/deepseek-r1-14b.env
nano config/models/deepseek-r1-14b.env       # 포트/스레드/ctx/양자화 조정
```

> 활성 모델 = `config/models/*.env` 에 존재하는 것. `run_all.sh` / `install_models.sh` 가
> 이 목록을 자동으로 쓴다. 더 추가하려면 `.gguf` 파일/슬러그만 다른 프로파일을 추가하면 된다.
> (모델별 HF_REPO/MODEL_FILE/LLAMA_PORT/THREADS/CTX_SIZE/KV_CACHE 는 각 프로파일이 담당)

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

다운로드:
```bash
bash scripts/download.sh deepseek-r1-14b   # ~8.9GB
```
`~/models/<파일>` 로 저장. 중단 시 재실행하면 이어받기.

---

## 3) 테스트 실행 (백그라운드) + 스모크

```bash
bash scripts/run_all.sh            # config/models/*.env 전부 백그라운드 시작
```
- 서버 READY 로그를 확인 후(로드 몇 분) 다른 터미널에서:
```bash
bash scripts/test_server.sh deepseek-r1-14b
# 원격이면:
LLAMA_HOST=<서버IP> bash scripts/test_server.sh deepseek-r1-14b
```
alias 확인: `curl http://127.0.0.1:8081/v1/models`

테스트 종료/상태:
```bash
bash scripts/run_all.sh --stop
bash scripts/run_all.sh --status
```

---

## 3b) 밤새 장문 생성 (백그라운드 + 파일 저장)

긴 문서(교재 등)를 한 번의 응답으로 생성해 파일로 남기되, SSH 를 끊어도 계속 돌리는 헬퍼.

```bash
# 1) 지시(프롬프트)를 파일로 준비 - 길어도 됨
cat > /tmp/prompt.md <<'EOF'
고등학교 물리 1권 목차 요약 작성에 이어서, ~컨텍스트 한도 안의 분량까지 상세 본문을 이어 써 줘.
EOF

# 2) 백그라운드 시작 (nohup → 로그아웃해도 계속)
bash scripts/overnight_gen.sh start deepseek-r1-14b /tmp/prompt.md
#   -> job: server/output/deepseek-r1-14b-<시각>/ ... 에 pid/로그 기록

# 3) 아침에 완료 확인
bash scripts/overnight_gen.sh status
bash scripts/overnight_gen.sh status server/output/deepseek-r1-14b-<시각>/
#    완료 시 <job>/content.md 에 최종 내용
```

> ⚠️ 한 번의 요청 = 컨텍스트(여기 16384) 안의 출력까지만. 전체가 그보다 훨씬 길면 이 헬퍼 단독으론 한 조각만 생성됨(여러 번 이어 쓰려면 프롬프트를 조각별로 재구성 필요).
> 참고: 생성 동안 그 포트(슬롯)를 점유하므로, 동시에 다른 요청을 보내면 대기할 수 있음.

---

## 4) 상시 데몬화 (systemd, 재부팅 자동) + 방화벽

3단계 데몬을 종료한 뒤(중복 방지):
```bash
bash scripts/install_models.sh           # 활성 모델(deepseek-r1-14b) enable+start
# 수동 인스턴스: sudo systemctl enable --now myllm-llama@deepseek-r1-14b
```

관리 (유닛 `myllm-llama@deepseek-r1-14b`):
```bash
systemctl status myllm-llama@deepseek-r1-14b
journalctl -u myllm-llama@deepseek-r1-14b -f
sudo systemctl restart myllm-llama@deepseek-r1-14b
sudo systemctl stop myllm-llama@deepseek-r1-14b

# 방화벽
sudo ufw allow 8081/tcp

# 서버 IP
hostname -I
```

---

## 5) 클라이언트(VS Code) 연결

클라이언트 컴퓨터의 VS Code 에서 `Continue` 확장 설치 후,
`~/.continue/config.yaml` 를 `client/continue/config.yaml.example` 를 참고해 작성:
- deepseek-r1-14b → `http://<서버IP>:8081/v1` (chat)

자세한 내용은 저장소 루트 `README.md` 및 `PLAN.md` 참고.

---

## 문제 해결

| 증상 | 대응 |
|------|------|
| 모델 로드 실패/arch 오류 | llama.cpp 구버전 → `01_setup_llamacpp.sh` 재실행(master) |
| 응답에 장문 chain-of-thought | R1 특성상 억제 불가. 로그로 진행 상태 확인 |
| 포트 못 잡음 | `run_all.sh --status`, `ss -ltnp 8081` 로 프로세스 확인 |
| 느림(정상) | 14B dense CPU = ~6-7 t/s. KV_CACHE q8_0 로 소폭 개선 시도 |
| 클라이언트 연결 안 됨 | `test_server.sh` 로 서버 먼저, IP/방화벽/`apiBase`의 `/v1` 확인 |
