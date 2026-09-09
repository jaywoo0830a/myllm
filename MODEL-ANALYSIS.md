# MODEL-ANALYSIS — CPU-only 다중 모델 배치의 수학적 분석

> 타깃 하드웨어: **AMD Ryzen 9 9700X (8코어/16스레드, Zen5) · DDR5 64GB · CPU-only**
>
> 이 문서는 myLLM 리포의 다중-모델 배치(PLAN.md / `server/scripts/*`)를 이상적 자원 배분 모델과 대조해
> **왜 "역할당 대표 1개 + 14B 단독" 이어야 하는지**를 숫자로 설명한다.
> 모든 수식은 KaTeX 문법이며 `README`에서 표시 가능하다.
>
> **문서 성격:** §1 이 이상적 수학 모델, §2 가 과거 문제점 → 조치 → 이행 상태 이력, §3 이 현재 재고와
> 남은 작업. 과거 삭제된 잔재(worker2~4, mistral 등)는 §2 의 해결 기록으로만 남는다.

---

## 1. CPU-only LLM 배치의 이상적 수학 모델

### 1.1 디코딩은 메모리 대역폭 결합 문제 (M1)

자기회귀 디코딩은 토큰마다 모델 **전체 가중치를 메모리에서 한 번 읽는다**.
CPU 연산은 충분히 빠르므로 병목은 **메모리 대역폭**이다.

$$
\tau_d \;=\; \frac{M_w}{B_{\text{mem}}}
\qquad\Rightarrow\qquad
\upsilon_{\text{dec}} \;=\; \frac{B_{\text{mem}}}{M_w}
$$

- `M_w` : 모델 가중치 상주 크기 (GGUF + 오버헤드)
- `B_mem` : 실효 메모리 대역폭 (DDR5-5600 2채널 이론 ~89 GB/s, 실효 ~45–55 GB/s)

| 모델 | M_w | 예상 `υ_dec` (B_mem ≈ 45GB/s) |
|---|---|---|
| 7B Q4_K_M | ~4.7 GB | **~7–9 tok/s** |
| 14B Q5_K_M | ~9.9 GB | **~4–5 tok/s** |

**핵심 정리 — 디코딩은 "동시 서버 수"가 아니라 "동시 생성 GGUF 종류"에 좌우된다.**

$$
\sum_i \upsilon_i \;\le\; \upsilon_{\text{tot}} \;=\; \frac{B_{\text{mem}}}{\overline{M}}
$$

1개 모델이 8 tok/s면 **동시 4개 서버는 각각 ~2 tok/s**로 총량은 그대로다.
→ 동시 프로세스 수를 늘려도 총 처리량은 늘지 않고 **레이턴시와 메모리만 는다.**
**결론: 병렬(프로세스 수 늘리기, `--parallel N`)은 CPU 에서 무의미하므로 사용하지 않는다.**
→ 역할은 항상 **대표 1개 인스턴스**만 두고 요청은 순차 처리한다.

### 1.2 프리필은 연산 결합 문제 (M2)

프롬프트(in-context) 처리 속도는 8코어 + AVX‑512 기준:

$$
t_{\text{prefill}} \;=\; \frac{n_{\text{in}}}{\upsilon_{\text{pre}}}
\qquad
\upsilon_{\text{pre}}^{\text{7B}}\approx 150\text{–}300,\quad
\upsilon_{\text{pre}}^{\text{14B}}\approx 60\text{–}120\ \text{[tok/s]}
$$

입력이 큰 작업(판사·세터)은 **프리필 시간이 지배적**이다.

### 1.3 메모리 예산 방정식 / OOM 판별식 (M3)

$$
\sum_{r\in R} n_r\, R_r(\text{ctx}) \;\le\; 0.85 \times 64\,\text{GB}\;\approx\; 54\,\text{GB}
$$

각 서버의 상주 크기:

$$
R_r(\text{ctx}) \;=\; \underbrace{M_w}_{\text{GGUF}} \;+\; \underbrace{KV(\text{ctx})}_{\text{KV 캐시}} \;+\; \underbrace{O}_{\text{오버헤드}}
$$

KV 캐시는 컨텍스트 토큰당:

$$
KV \approx 2 \times n_{\text{layers}} \times n_{\text{kv\_heads}} \times d_{\text{head}} \times \text{dtype}
$$

| 모델 | KV/tok (FP16) | KV @ ctx 16K | q8_0이면 |
|---|---|---|---|
| Qwen2.5-7B (kv_heads=4) | ~56 KB | ~0.9 GB | ~0.45 GB |
| Qwen2.5-14B (kv_heads=8) | ~192 KB | ~3.0 GB | ~1.5 GB |

### 1.4 지연 예산(SLA) 검증식 (M4)

스테이지 실시간 지연:

$$
T_{\text{stage}} \;=\; \underbrace{\frac{n_{\text{in}}}{\upsilon_{\text{pre\_d}}}}_{\text{prefill}} + \underbrace{\frac{n_{\text{out}}}{\upsilon_{\text{dec}}}}_{\text{decode}}
$$

### 1.5 최적 배치 = 자원 할당 최적화 (M5)

$$
\begin{aligned}
\min_{\{n_r\}} \quad & \sum_{r} n_r\, R_r(\text{ctx}_r) \\[4pt]
\text{s.t.} \quad
  & \sum_{r} n_r\, t_r \;\le\; 16   & \text{(스레드 총량)} \\
  & \sum_{r} n_r\, R_r \;\le\; 54\,\text{GB} & \text{(메모리 총량)} \\
  & n_r \le |\mathcal{G}_r|\quad \text{exactly} \;=\; |\mathcal{G}_r| \text{ 종류 수} &
\end{aligned}
$$

> **최적 인스턴스 수 = "서로 다른 GGUF 파일 수"이며, 총 인스턴스 수가 아니다.**

**이 하드웨어의 수치 궁극값 (이상적 배치)**

| 프로세스 | GGUF | resident | threads | 역할 |
|---|---|---|---|---|
| A | Qwen2.5-7B-Instruct | ~6 GB | 8 | parser |
| B | Qwen2.5-7B-Instruct | ~6 GB | 8 | worker1 |
| C | Qwen2.5-Coder-7B | ~6 GB | 8 | coder1 |
| D | DeepSeek-R1-7B (on-demand) | ~6 GB | 8 | reasoner |
| E | 14B Setter (E/F 상호배타) | ~12 GB | 8 | problem set |
| F | 14B Judge (E/F 상호배타) | ~12 GB | 8 | verify |
| G | bge-small (in-process) | ~1 GB | – | embedding |

피크 동시 상주 ≈ $6+6+6+1+12 \approx 31\,\text{GB}$
→ **64GB 의 절반 이하.** 토큰 레이트: 7B ≈ 7–9 tok/s, 14B ≈ 4–5 tok/s (물리적 상한).

---

## 2. 문제점 → 조치 → 이행 상태 (이력)

과거 리포가 이상적 모델에서 어긋나던 지점들과, 그것이 어떻게 해결됐는지/남아 있는지를 기록한다.
상태: ✅ 해결 ・ 🟡 부분/잔여 ・ ⬜ 미해결

### ✅ P1. `start_all.sh` — 9중 동시 로드 → "역할당 대표 1개"

**과거:** parser + worker1~4 + coder1~4 + reasoner **총 9개 동시 로드**:

$$\text{메모리}:\; 9\times6\,\text{GB}\approx 54\,\text{GB}\qquad
\text{스레드}:\; 9\times8 = 72 \;\gg\; 16$$

- PLAN의 "40GB+ 여유" 정면 위반, OOM/스왑 직전 수치였고 스레드 72개 과잉 할당으로 오히려 저하.

**조치:** worker2~4 · coder2~4 의 env 예제 **삭제** + `start_all.sh` 를 **parser + worker1 + coder1 만** 로드로 교체.
reasoner 는 `up.sh reasoner`, 14B(setter/judge) 는 `start_heavy.sh` 로 on-demand 상호배타.
→ **이행 완료** (피크 상시 상주 ≈ 15GB).

### ✅ P2. `llama_serve_generic.sh` — 튜닝 플래그 미적용 → 반영

**과거:** `exec llama-server`에 `-m, --alias, --host, --port, --ctx-size, -t`만 전달되어
`KV_CACHE`, `BATCH/UBATCH` 가 **미전달 → 무시**됨 (판사 KV 가 계획의 2배, 워커 4개가 각자 4.7GB 중복 로드).

**조치:** `-b/-ub(배치)`, KV 캐시 양자화 플래그를 명령줄에 반영.
- llama.cpp build 10858+ 는 옛 통합 `--cache-type "k:...,v:..."` 제거 → **`--cache-type-k`/`--cache-type-v` 분리 플래그** 사용.
- `KV_CACHE` 가 비면 양자화 생략(기본 f16) 하도록 방어.
- `MODEL_SLUG` 없이 직접 실행 시 사용법 안내 후 종료(가드) 추가.
→ **이행 완료**.

### 🟡 P3. 모델별 균일 `CTX_SIZE` → 역할별 비대칭화

파서/판사는 출력이 극히 짧으므로 컨텍스트를 줄여 KV 를 절약한다.

$$R_r \propto \text{ctx}_r \;\Rightarrow\;
\text{작은 판사/파서 }\text{ctx}\downarrow,\ \text{큰 세터/리즈너 }\text{ctx}\uparrow$$

**현재:** `parser.env` 는 8192 로 이미 축소. judge/setter/reasoner 는 각 env 에서 더 세밀 조정 가능.
→ **부분 이행** (역할별 컨텍스트 조정은 env 로 열려 있음).

### ✅ P4. 출력 토큰 예산 vs CPU 속도의 시간 수학 → 문서화

Reasoner `max_tokens=2000`:

$$t_{\text{reasoner}} \approx \frac{2000}{7\text{–}9} \approx 220\text{–}290\ \text{초} \;(4\text{–}5분)$$

판사는 출력만 보면 1초이지만 **입력 프리필 때문에 총 5–10초**가 현실적 SLA.
→ PLAN.md/STATUS.md 의 시간 지표를 **실측 기반(프리필 포함)**으로 교정 완료.

### ✅ P5. `performance_tuning.md` — Zen5 / 7B·14B 파이프라인 교정

**과거:** 9700X 를 "Zen 3"로, 타깃을 "Mistral-Small-24B"로 기술.
**조치:** `-march=native`(Zen5 AVX‑512) + Qwen2.5-7B/14B·DeepSeek-R1-Distill 파이프라인 기준으로 전면 갱신.
→ **이행 완료**.

### ✅ P6. 잔재·명칭 드리프트 제거

- `mistral-large.env(.example)`, `llama_serve_mistral.sh` → **삭제**.
- worker2~4 / coder2~4 `.env.example` → **삭제**.
- (잔여 참고) `contract.yml` 의 `generator/retriever/embedder` vs PLAN 의 `worker/coder/judge/setter` 는
  API 명세 단계의 명칭 차이로, 오케스트레이터 구현 시 맞춰야 할 항목.

### ⬜ P7. 임베딩·RAG 미구현 (contract 만 존재)

`/embed,/retrieve,/generate`(contract.yml)·`embedding` 슬러그(model_registry.py)는 **구현 전**.
bge-small 은 llama.cpp 보다 Python(sentence-transformers) 상주가 적합.
→ **남은 작업** (README top-level 의 "Next Steps" 참조).

---


## 3. 결론: 핵심 원리 + 현재 재고

$$
\boxed{%
\begin{gathered}
\text{① 디코딩은 대역폭 결합} \;\Rightarrow\; \text{최적점 = "동시 GGUF 종류 수"}\\\n\text{② 최적 배치는 이미 이행됨: 역할당 1개 상시 + 14B 단독 + KV q8_0}
\end{gathered}}
$$

**현재 상태 요약 (도표)**

| 영역 | 상태 | 비고 |
|---|---|---|
| 배치 로드 (`start_all.sh`) | ✅ | parser+worker1+coder1 상시, reasoner/14B on-demand |
| 튜닝 플래그 (`llama_serve_generic.sh`) | ✅ | `-b/-ub`, `--cache-type-k/-v` 반영, 가드 추가 |
| 문서 (PLAN/README/performance) | ✅ | Zen5·7B/14B·새 플래그명 기준 |
| 잔재 제거 (mistral, worker2~4) | ✅ | 삭제 완료 |
| 역할별 CTX 세밀화 (judge/setter/reasoner env) | 🟡 | env 로 조정 가능, 필요 시 추가 |
| 임베딩·RAG (contract 전용) | ⬜ | 오케스트레이터/임베더 구현 필요 (Next Steps) |
| Script Runner API (`scripts/api`) | ✅ | worker 슬러그 제어용 FastAPI 추가 (포트 18080) |

**남은 작업 (우선순위)**
1. **오케스트레이터 + RAG** — `/run-plans` 류 파이프라인 및 `/embed,/retrieve` 구현. (P7)
2. **역할별 CTX/KV 미세 조정** — judge/setter/reasoner env 에서 실제 서비스 톤에 맞춰 확정. (P3)
3. **명칭 정렬** — contract.yml(parser/embedder/retriever/generator) 과 오케스트레이터 역할명 통일. (P6 잔여)
