# 서버(9700X) 배포 & 다른 서비스가 호출하기 — 실행 가이드

이 문서는 **실제 9700X 서버**에 Script Runner API(포트 18080)를 띄우고,
**다른 내부 서비스가 이 API 를 호출해 호스트의 모델(llama-server)을 제어**하게 하는 절차다.

> **✅ 본 목적(호스트 모델 제어)에는 systemd 로 호스트에서 API 를 띄운다.**
>
> - `up` / `down` / `start_heavy` 는 **호스트의 llama-server PID 를 관리**(`server/run/*.pid`)
>   하므로, API 프로세스도 **호스트에서** 실행해야 이 PID 를 볼 수 있다.
> - Docker 컨테이너는 별도 PID 네임스페이스라 호스트 llama-server 를 건드릴 수 없다.
>   → **Docker 는 "상태 조회 전용" 대안**일 뿐, 모델 제어 목적에는 쓰지 않는다 (§8 참고).

---

## 0. 전제

- 저장소가 서버에 클론되어 있음: `/home/<user>/myllm` (아래 예시는 `/srv/myllm` 로 가정)
- `python3` + `pip` 사용 가능 (fastapi/uvicorn 미설치 시 아래 설치)
- 서버에 `llama.cpp` 와 모델 GGUF 가 이미 있어 `up.sh` 가 동작하는 상태

---

## 1. 호스트 파이썬 의존성 설치 (1회)

> API 를 **호스트에서** 실행하므로 호스트의 python3 에 fastapi/uvicorn 을 깐다.
> (도커 이미지에는 이미 들어 있지만, 위 목적상 호스트 파이썬이 필요하다.)

```bash
cd /srv/myllm
pip install -r scripts/api/requirements.txt
# 또는: python3 -m pip install 'fastapi>=0.110' 'uvicorn[standard]>=0.23' 'pydantic>=2'
```

---

## 2. 빠른 테스트 (시작 전 확인)

```bash
# 터미널 1 — 개발 모드로 띄우기 (reload 켬)
bash scripts/api/run_local.sh 18080

# 터미널 2 — 헬스체크
curl -s http://localhost:18080/health
# → {"ok":true,"version":"1.0.0","bash_available":true,"scripts_dir":"/srv/myllm/server/scripts"}
```

되면 Ctrl-C 로 끄고 아래 데몬(3)으로 넘어간다.

---

## 3. systemd 로 호스트에서 상시 서비스 등록 (본 목적)

> 모델 제어(up/down/start_heavy)가 목적이므로 **호스트에서** 실행한다.

저장소의 unit 템플릿을 설치하고 경로/사용자를 치환한다.

```bash
cd /srv/myllm
sudo cp scripts/api/myllm-api.service /etc/systemd/system/

sudo sed -i \
  -e "s|{{USER}}|$(whoami)|" \
  -e "s|{{SCRIPT_DIR}}|/srv/myllm|" \
  /etc/systemd/system/myllm-api.service

# [보안 필수] 토큰 설정 (주석을 풀고 강한 값으로 교체)
sudo sed -i \
  's|^# Environment=EXTERNAL_TOKEN=CHANGE_ME_STRONG_SECRET|Environment=EXTERNAL_TOKEN='"$(echo -n "$(hostname)-$(date +%s)" | base64 | head -c32)"'|' \
  /etc/systemd/system/myllm-api.service

sudo systemctl daemon-reload
sudo systemctl enable --now myllm-api
systemctl status myllm-api --no-pager
```

관리 명령:

```bash
systemctl status myllm-api        # 상태
journalctl -u myllm-api -f -n 50  # 로그 실시간
sudo systemctl restart myllm-api  # 재시작
```

---

## 4. 방화벽 열기 (원격 호출용)

같은 머신이면 불필요. LAN/다른 서버에서 호출하려면:

```bash
# ufw 인 경우
sudo ufw allow 18080/tcp
sudo ufw status

# firewalld 인 경우
sudo firewall-cmd --permanent --add-port=18080/tcp
sudo firewall-cmd --reload
```

> 보안: **반드시 EXTERNAL_TOKEN 을 설정**할 것. 안 하면 토큰 없이 액션이 가능함.
> 서버가 공용 인터넷에 노출돼 있으면 더 강하게: 역방향 프록시(nginx) + TLS + IP 제한.

---

## 5. 다른 서비스(클라이언트)가 호출하는 방법

### 5.1 상태/액션 확인

```bash
BASE="http://<서버IP>:18080"
TOK="<위에서 만든 토큰>"

# 헬스
curl -s "$BASE/health"

# 허용된 액션·모델 목록
curl -s "$BASE/v1/allowlist" -H "Authorization: Bearer $TOK"

# 상태 리포트 생성 (조회)
curl -s -X POST "$BASE/v1/run" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOK" \
  -d '{"action":"status"}'
```

### 5.2 정기 폴링 (예: 5분마다 status)

```bash
# cron 예: crontab -e
*/5 * * * *  curl -s -X POST http://127.0.0.1:18080/v1/run \
  -H 'Content-Type: application/json' -H "Authorization: Bearer <TOK>" \
  -d '{"action":"status"}' >/dev/null 2>&1
```

### 5.3 특정 작업 트리거 (예: 모델 시작, 14B 단독)

```bash
# 모델 서버 시작
curl -s -X POST "$BASE/v1/run" -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' -d '{"action":"up","arg":"parser"}'

# 14B 판사 단독(on-demand, 상호배타)
curl -s -X POST "$BASE/v1/run" -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' -d '{"action":"start_heavy","arg":"judge"}'
```

### 5.4 Python 클라이언트 예

```python
import os, requests

BASE = "http://<서버IP>:18080"
H = {"Authorization": "Bearer " + os.environ["MYLLM_TOKEN"]}

# 상태 조회
r = requests.post(f"{BASE}/v1/run", json={"action": "status"}, headers=H, timeout=60)
print(r.json()["stdout"])

# 업을 요청하고 성공 여부 확인
r = requests.post(f"{BASE}/v1/run", json={"action": "up", "arg": "reasoner"}, headers=H, timeout=300)
print(r.status_code, r.json().get("ok"), r.json().get("stderr"))
```

---

## 6. 권장 호출 부하 (병렬 금지 원칙)

CPU(메모리 대역폭 결합) 환경이므로 API 호출을 **병렬로 하지 마라**.
동시에 여러 요청을 보내도 총 처리량은 늘지 않고 각각 느려진다.

```text
✓ 요청을 순차 큐로 보낸다   (각 응답이 빨라짐)
✗ 동시에 4개씩 쏜다          (대역폭이 나눠져 모두 느려짐)
```

- 단건 응답 시간: `status` <1s, `up/down`(모델 부팅 제외) 수 초 이내.
- 타임아웃 한도는 서비스에 `MYLLM_CMD_TIMEOUT`(초) 로 설정됨. 기본 180s.

---

## 7. 오류 코드

| HTTP | 의미 |
|------|------|
| 400 | 허용되지 않은 action / arg (화이트리스트 밖) |
| 401 | EXTERNAL_TOKEN 불일치 / Bearer 누락 |
| 200 | 정상. `ok`/`returncode`/`stdout`/`stderr` 확인 |

모든 응답이 JSON 이며, 스크립트 stdout/stderr 를 그대로 돌려주므로
호출 측 로그에 붙이면 디버깅이 쉽다.

---

## 8. 실행 방식 정리

| 항목 | Docker Compose(18080) | **systemd 호스트(18080) ← 본 목적** |
|------|-----------------------|-----------------------------------|
| `status` / `allowlist` / `health` / `log` | ✅ 동작 | ✅ 동작 |
| `up` / `down` / `start_heavy` | ⚠ 커널 llama-server PID 노출 불가 → **실패** | ✅ 실제 호스트 PID 제어 |
| 재시작 관리 | `docker compose` | `systemctl` |
| 권장 용도 | 상태 조회 전용(조회만 필요할 때) | **호스트 모델 제어(본 목적)** |

> **두 방식을 같은 18080 포트로 동시에 띄우면 충돌**한다.
> **호스트 모델 제어가 목적이면 `systemd` 방식 하나만** 쓰고, 도커는 띄우지 않는다.