# stemer/study — diffuse(LLaDA-8B) 백엔드 문맥 운용 지침

> 작성: 2026-09-08 · 코드베이스: `ubuntu@192.99.201.121 ~/projects/stemer/study` (git HEAD `628aa9b`)
> **가정: 처리 가능한 문맥 길이 = 4,096 tokens**
> 백엔드: diffuse-cpp `LLaDA-8B-Instruct` (OpenAI 호환 `/v1/chat/completions`, 서버 `8081`)

---

## 0. 이 문서가 다루는 것

과거 이 파이프라인은 llama-server **DeepSeek-R1-14B**(CPU, 8081)를 썼고, 그때
느림·출력전 멈춤을 진단해 **입력예산 4096·부분분할·파트 max 하향·재시도 완화**(A~D)를
코드에 반영했다(git: `c7361aa`, `42e211e`, `628aa9b`).

지금 백엔드는 **diffuse(LLaDA-8B)** 로 바뀌었고, 본 문서는 **"전체 프롬프트
(시스템+통과 passage+생성분) 를 문맥 4,096 토큰 안에 담는다"**는 가정 아래,
현재 study 코드가 diffuse-LLaDA 를 올바르게 호출하는지와 문맥 4,096 한계 안에서
무엇을 바꿔야 하는지를 정리한다.

> **중요한 아키텍처 차이**: diffusion(LLaDA) 은 autoregressive(R1)과 달리
> "프롬프트+전체 생성문단을 함께 넣고 병렬 정제" 한다. 즉
> **문맥 소비 = 시스템 템플릿 + passage + 한 번에 만들 마크다운 길이** 전부가
> 한 요청 안에서 합산**된다. 문맥 4096 이라면 **한 요청에서 생성 본문도 그 안에** 들어가야 하므로
> "1회에 긴 part 완성"은 물리적으로 불가능하다.

---

## 1. 현재 study 코드 값 (git HEAD, 실측)

`study_lib/generate_free.py`
```python
_PART_MAX          = {"concept": 6000, "examples": 12000, "practice": 14000}  # L196
MAX_INPUT          = 16384        # L305 주석: "총 ctx = 16384 (8081 llama-server)"  ← 여전히 R1 값
_SCAFFOLD_EST      = 640          # L307
DEFAULT_INPUT_TOKENS = 4096       # L308 (권고안 A 반영: 입력 passage 기본)
# input_budget(): env LOCAL_FREE_INPUT_TOKENS 로 재정의, cap = 16384-640   L312
```

`study_lib/llm_local.py`
```python
# LOCAL_LLM_CHAT 기본 "auto" → v1/chat 우선, 실패 시 /completion 폴백   L58
# complete(): reasoning 이 content 를 삼키면 max 를 +2048 씩 3회까지   L149-164
# LocalClient.base_url = LOCAL_LLM_BASE (기본 8080, 실제 운영은 8081 로 export)
```

현재 실제 `.env`: `LOCAL_LLM=1` 만 노출(LOCAL_LLM_BASE 없음 → 기본 8080).

---

## 2. 문맥 4,096 기준 — 지금 코드와 어긋나는 점

### A. "입력 passage 4096(채움)" 그대로면 전체는 4096 훨씬 초과
- `DEFAULT_INPUT_TOKENS = 4096` 은 **passage(입력)만의** 예산이다. 실제 요청엔
  시스템 템플릿(`_STD` + part 지시, 길 수 있음)과 생성문(최대 수천 토큰)이 더해진다.
- 문맥 4096 상정이면 passage 예산은 **4096 이 아니라 4096 − (시스템+생성분)** 만 남는다.
  예: 시스템 ~800 + 생성 ~2000 이면 passage 는 그나마 ~1000 토큰 뿐.

### B. `_PART_MAX`(6k·12k·14k) 생성 요구는 4,096 과 충돌
- examples 12000 / practice 14000 짜리 응답을 한 요청으로 만들려 애초에 프롬프트+생성
  이 4096 을 아득히 넘으므로 **하나의 complete() 로는 절대 완성 불가**.
- diffusion 이라 "생성 행이 높을수록" 이 아니라 **토큰 창이 곧 문맥 최대**이므로
  요청 자체가 거부/홀쪽하게 잘림.

### C. `MAX_INPUT = 16384` + cap(16384−640) 상수는 R1(무 ctx 16384) 잔재
- diffuse LLaDA 쪽은 **문맥 4096** 이므로 이 상수/캡 기준이 부적합 (상향 허용 가능성이
  실제 문맥을 초과로 유도).

### D. diffusion 은 "reasoning + 재시도 + α" 접근이 사실상 불필요/다르게 맞음
- diffuse 서버는 생성 `max_tokens` 를 "한 요청 청크"로, diffusion 로 채운다.
  문맥 4096 안에서 자동 정제되므로, R1 처럼 reasoning 이 content 를 삼켜 재시도할
  일은 구조적으로 줄어든다 — 하지만 문맥 초과로 인한 "홀쪽 출력" 은 여전히 발생 가능.

---

## 3. 권고 (문맥 4,096 실사용 기준, 적용 순서)

### P1(필수): "시스템+passage+생성" 합계를 4096 으로 보정할 입력 예산 계산으로 교체
`generate_free.py`
```python
# 문맥(창) 4096 이 실제 처리 가능 토큰총합
CTX_LIMIT   = 4096
SCAFFOLD    = _SCAFFOLD_EST   # 시스템 헤더+고정(실측으로 교정: < 1000 권장)
# 한 요청: 시스템 + passage + 생성. passage 예산 = CTX - 시스템 - 생성 여백
# (부분분할 P2 를 쓰면 각 요청의 passage 가 줄어 생성 여백을 만든다)
```
운영 상수: `LOCAL_FREE_INPUT_TOKENS` 를 **~1200 이하**로 두고, 시스템 템플릿을
**가능한 한 축약**해 passage + 생성 여백을 확보.

### P2(필수): 문맥 4096 은 "1 요청 1 소구획" 이니 부분분할·점증 생성을 기본으로
- diffusion 으로 `.md`(실제 수천 토큰)를 만들려면 **concept/examples/practice 를
  각각 더 작은 청크로 쪼개 여러 번 생성·누적**해야 한다.
- 이미 `run_free_parts` 로 3 part 분할돼 있으나, part 내부도 문맥 여백에 맞게
  분절(예: "4 개 예제 중 1~2 개씩 두 호출")로 이어붙이는 저장 로직이 필요.
- 각 요청의 **시스템+passage 소계를 ~1200~1500**, 그 위 생성 ~2500~2800 로.

### P3(필수): `_PART_MAX` 와 `MAX_INPUT` 상수를 문맥 계열로 교정
- `_PART_MAX`를 문맥 4096 안의 **한 요청에서 실제로 뽑는(생성하는) 크기**(≤ ~2800)로
  낮추고, "남은 본문은 다음 요청이 이어 생성"하게 한다.
- `MAX_INPUT = 16384` → diffusion 문맥을 반영한 값(또는 변수로 창 크기 주입). cap 도 동일.
- 생성 여백이 실제 문맥을 넘지 않도록 `input_budget → 4096-시스템-생성` 보정.

### P4(권장): 시스템 템플릿을 문맥 친화로 축약 (현재 상당히 김)
- `_STD` + 각 part 지시문이 R1 용으로 상세하다. 문맥 4096에선 시스템이 수백~천 토큰을
  삼키면 passage/생성 여백이 사라진다. 긴 전문은 **1회 상수로 강조/축약**하거나 첫 요청에만 전달.

### P5(확인/다듬음): `LocalClient`는 diffuse OpenAI 호환 서버를 그대로 호출할 수 있다
- study `llm_local`은 `/v1/chat/completions`(LOCAL_LLM_CHAT auto)를 쓰므로,
  `LOCAL_LLM_BASE=http://127.0.0.1:8081` 로 export 하면 **diffuse-LLaDA 서버**(8081)를
  그대로 부를 수 있다.
- 단 diffuse 서버의 `/v1/models` id 는 현재 "dream-v0-7b" 라 표기되나 동작엔 무관
  (같은 OpenAI 호환 레이어). 모델 무관이라 별도 수정 불필요.
- `temperature` 등 일부 값은 diffuse 쪽 기본(그리디+entropy_exit)이 우선하니,
  샘플링 제어가 꼭 필요하면 diffuse_server 쪽 파라미터로 맞춘다.

### P6(구현 전 반드시): 실제 요청이 몇 토큰으로 나가는지 계측해 상한을 인증
- 문맥 4096 하드리밋을 막는 로직이 study 쪽에 **아직 없다**(입력만 4096 으로 짠 상태).
  문자열/토큰 계측(`LocalClient.count_tokens`) 후 **전체(시스템+passage+생성분)이
  4096 을 초과할 요청은 생성 전 거부/분절**하게 하드리밋을 둔다.

---

## 4. 대상 파일/라인 요약 (diffuse 문맥 4096 로 맞출 지점)

| 파일 | 위치 | 현재 | 문맥 4096 목표 |
|---|---|---|---|
| `generate_free.py` | L305-308 | `MAX_INPUT=16384`, `_SCAFFOLD_EST=640`, `DEFAULT_INPUT_TOKENS=4096` | 창(문맥)상수를 4096 계열로, passage 만이 아니라 **총량** 예산 |
| `generate_free.py` | L196 | `_PART_MAX={concept:6000,examples:12000,practice:14000}` | 한 요청 생성 ≤ ~2800 (이어서 누적) |
| `generate_free.py` `run_free_parts` | — | 3 part 순차 | part 내부도 청크 분절·누적(문맥 여백 맞춰) |
| `llm_local.py` | L149-164 | reasoning 재시도 `+2048` | diffusion 에선 대부분 불필요; 대신 문맥초과 시 더 작은 생성 제안 |
| `llm_local.py` | L58/L28 | chat auto / 기본 8080 | 운영 `LOCAL_LLM_BASE=...:8081` export(현재 diffuse) |

---

## 5. 운영 실행 요약 (diffuse 8081 + ctx 4096)

```bash
cd ~/projects/stemer/study

# 1) 8081 = diffuse LLaDA 를 쓰도록
export LOCAL_LLM_BASE=http://127.0.0.1:8081
#    (필요 시) LOCAL_LLM_CHAT=1 로 chat(OpenAI 호환) 강제 — diffuse 서버는 chat 하나만 노출

# 2) passage 총 예산은 문맥 4096 대비 아주 보수적으로(시스템+생성분 제외). 예)
export LOCAL_FREE_INPUT_TOKENS=1200   # 시스템/생성 여백 남겨 문맥 4096 안쪽

# 3) 생성은 반드시 부분분할/점증으로 (examples 12k 를 4096 문맥에서 한 방에 만드는 것은 불가)
python -m study_lib.cli generate-free --part concept ...        # (실제 진입 별도)
python -m study_lib.cli generate-free --part examples ...
python -m study_lib.cli generate-free --part practice ...
```

---

## 부가 참고

- git HEAD `628aa9b` 기준: (a) 입력예산 4096 반영(A), (b) 부분분할·maxt 하향(B/C),
  (c) gentle retry(D), (d) chat-first transport(ch R1 reasoning-leak 방지).
  이들은 **R1(무 ctx 16384)** 을 기본 전제로 짠 값 — 지금 diffuse **4096 문맥**으로는
  `MAX_INPUT/_PART_MAX/시스템 길이` 재조정과 **요청-단위 하드리밋 추가**(P6)가 남는다.
- 8081 서버: `mylm-diffuse@llada.service` (systemd, LLaDA-8B). 백엔드 교체/되돌림은
  해당 유닛을 다룬다.
