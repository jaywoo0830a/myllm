# STATUS — 현재 모델 운용 현황

> 생성: 2026-09-09 14:52:08 KST  ·  호스트: DESKTOP-S0008G0
> (이 서버에서 실행 시 실제 프로세스/메모리 기준, `--remote` 면 저장소 기준)

## 1. 시스템 요약

| 항목 | 값 |
|---|---|
| CPU | AMD Ryzen 7 260 w/ Radeon 780M Graphics  (cores=16, threads=16) |
| RAM | total=15.3 GB, used=3.4 GB, avail=11.8 GB |
| 스왑 | - |
| 설계 기준(ideal) | 9700X(8C/16T) · DDR5 64GB · CPU-only |

## 2. 모델별 상태

| 역할 | 모델(GGUF) | 포트 | 상태 | PID | RSS(MB) | 실제 실행 옵션(일부) |
|---|---|---|---|---|---|---|
| 분배(Parser) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 8081 | ▼(down) | - | 0 | - |
| 일꾼(Worker) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 8082 | ▼(down) | - | 0 | - |
| 일꾼(Worker) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 8083 | ▼(down) | - | 0 | - |
| 일꾼(Worker) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 8084 | ▼(down) | - | 0 | - |
| 일꾼(Worker) | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 8085 | ▼(down) | - | 0 | - |
| 코더(Coder) | `qwen2.5-coder-7b-instruct-q4_k_m.gguf` | 8086 | ▼(down) | - | 0 | - |
| 코더(Coder) | `qwen2.5-coder-7b-instruct-q4_k_m.gguf` | 8087 | ▼(down) | - | 0 | - |
| 코더(Coder) | `qwen2.5-coder-7b-instruct-q4_k_m.gguf` | 8089 | ▼(down) | - | 0 | - |
| 코더(Coder) | `qwen2.5-coder-7b-instruct-q4_k_m.gguf` | 8090 | ▼(down) | - | 0 | - |
| 추론가(Reasoner) | `DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf` | 8088 | ▼(down) | - | 0 | - |
| 문제생성(Setter/14B) | `Qwen2.5-14B-Instruct-Q5_K_M.gguf` | 8091 | ▼(down) | - | 0 | - |
| 판사(Judge/14B) | `DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf` | 8092 | ▼(down) | - | 0 | - |

## 3. 메모리 요약

- 실행 중 llama-server RSS 합계 ≈ **0 MB** (위 표).
- OS/RAG/캐시 포함 전체 사용량은 1번 시스템 요약의 RAM used 를 보세요.

## 4. 권장 상태 대비 현재

| 구분 | 권장 상주 | 실행 |
|---|---|---|
| 상시 | parser + worker1 + coder1 (≈15GB) | `bash scripts/start_all.sh` |
| on-demand | worker2~4, coder2~4, reasoner | `bash scripts/up.sh <slug>` |
| 14B 상호배타 | setter ↔ judge (둘 중 하나만) | `bash scripts/start_heavy.sh setter\|judge` |

> 현재 떠 있는(▲) 모델이 위 권장과 다르면 불필요한 인스턴스를 내리세요:
>   `bash scripts/down.sh <slug>`

## 5. 이상적으로 어떻게 써야 하는가

**핵심 원리 (수학: `MODEL-ANALYSIS.md` §1)**
- 디코딩(토큰 생성)은 **메모리 대역폭 결합**입니다. 프로세스를 병렬로 늘려도 총 처리량은
  늘지 않고 RAM·스레드만 낭비되어 오히려 느려집니다.
- 그래서 **"상시 = 역할별 대표 1개씩만, 14B = 둘 중 하나만(단독)"** 이 원칙입니다.

**역할별 로드 가이드**
| 목적 | 실행 |
|---|---|
| 요약/검색/분배 | `bash scripts/start_all.sh` (parser+worker1+coder1) |
| 추가 일꾼(요약 병렬) | `bash scripts/up.sh worker2` |
| 코드 작성/리뷰/픽스 | 상시 coder1 (필요시 worker2~4 처럼 up.sh) |
| 딥추론/증명(긴 출력) | `bash scripts/up.sh reasoner` (최대 2000tok → CPU 에선 수 분) |
| 문제 생성(14B) | `bash scripts/start_heavy.sh setter` (독점) |
| 검증(14B, GBNF) | `bash scripts/start_heavy.sh judge` (setter 와 배타) |

**속도 가이드 (CPU 9700X)**
- 7B(Q4): **~7–9 tok/s** · 14B(Q5): **~4–5 tok/s**
- "판사 1초"는 GBNF 로 출력은 짧으나 **입력 프리필 때문에 총 5–10초**가 현실적 SLA.
- 여러 역할에 요청을 흩뿌리지 말고 **한 번에 한 흐름**으로 굴리면 각 응답이 빨라집니다.

---
*생성 스크립트: `server/scripts/status_report.sh` · 상세 자원 모델: `MODEL-ANALYSIS.md`*
