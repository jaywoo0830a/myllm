# Performance Tuning Guide for myLLM on AMD Ryzen 9700X (DDR5 64GB)

> 타깃: **AMD 9700X (8코어/16스레드, Zen 5 / Granite Ridge, AVX‑512 지원) · DDR5 64GB · CPU‑only**
> 대상 워크로드: Qwen2.5‑7B / Qwen2.5‑Coder‑7B / DeepSeek‑R1‑Distill‑7B / Qwen2.5‑14B / DeepSeek‑R1‑Distill‑14B (multi‑agent)
>
> 자원 배분 원칙은 **MODEL‑ANALYSIS.md §1** 을 따른다.
> 디코딩은 메모리 대역폭 결합(M1) → 프로세스 수를 늘려도 총 처리량은 증가하지 않는다.
> 즉, **역할은 항상 대표 1개만 띄우고(병렬 없음), 14B 는 단독 on‑demand** 로 운용.

---

## 1. Build `llama.cpp` with optimal flags (Zen 5)

9700X 는 **Zen 5** 프로세서로 AVX‑512 를 지원한다. `-march=native` 가 가장 안전하고
(Zen 5 전용 지시어 최대 활용), 원하면 `-march=znver5` 로 세밀 타깃팅도 가능하다.
(구버전 문서의 `znver3` 는 Zen 3 용 — 9700X 에는 부적합.)

```bash
git clone https://github.com/ggerganov/llama.cpp.git && cd llama.cpp
mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-march=native -O3 -funroll-loops" \
  -DCMAKE_CXX_FLAGS="-march=native -O3 -funroll-loops" \
  -DGGML_AVX512=ON \
  -DGGML_OPENBLAS=OFF \
  -DGGML_CUDA=OFF
make -j$(nproc)
cp llama-server /path/to/myllm/server/scripts/
```

**왜?** `-march=native` + `GGML_AVX512=ON` → Zen 5 의 AVX‑512 커널을 사용해
행렬곱(프리필) 처리량을 극대화한다 (M2: 프리필은 연산 결합).

---

## 2. Thread count

`THREADS` 는 **물리 코어 수(8)** 기준으로 설정한다. SMT(16) 는 LLM 디코딩에서
컨텐션만 키우므로 사용하지 않는 것을 권장한다.

| 설정 | 값 | 비고 |
|------|-----|------|
| `THREADS` | `8` | 상시 모델당 8. 동시 상주가 여러 개면 합이 16 을 넘지 않게 |

**⚠️ multi‑process 주의:** 상시 상주 주는 `parser + worker1 + coder1`(start_all.sh).
14B(setter/judge) 는 **상호배타**라 어느 한쪽만 떠 있다 (start_heavy.sh).
그래야 스레드/메모리 합이 하드웨어 내에서 유지된다.

---

## 3. KV‑Cache quantisation

모델 가중치는 Q4/Q5 이므로 KV 캐시를 `q8_0` 으로 양자화하면 속도+메모리를 함께 잡는다.
`llama_serve_generic.sh` 가 `--cache-type k:q8_0,v:q8_0` 로 실제 반영한다.

- 7B @ ctx 16K ≈ 0.9 GB(FP16) → q8_0 로 **~0.45 GB**
- 14B 판사/세터: CTR 축소(8K) + q8_0 로 KV 할당을 크게 절감

```bash
export KV_CACHE="q8_0"   # 각 server/config/models/*.env 에 이미 설정
```

---

## 4. Memory‑bandwidth (병목 지배 요인)

DDR5‑5600 2채널 이론 ~89 GB/s, 실효 ~45–55 GB/s.
디코딩 최대 토큰율은 대역폭 ÷ 가중치 크기:

$$
\upsilon_{dec} = \frac{B_{mem}}{M_w}
\;\Rightarrow\;\ \text{7B Q4} \approx 7\text{–}9\,\text{tok/s},\quad
\text{14B Q5} \approx 4\text{–}5\,\text{tok/s}
$$

- 모델 GGUF 는 반드시 **NVMe SSD** 에 두어 로드 시 I/O 스톨을 막는다.

---

## 5. System‑wide tuning (Linux)

| 파라미터 | 값 | 설정 |
|----------|-----|------|
| `vm.swappiness` | `1` | 스왑 방지: `sudo sysctl -w vm.swappiness=1` |
| `fs.file-max` | `200000` | `sudo sysctl -w fs.file-max=200000` |
| `ulimit -n` | `65535` | `/etc/security/limits.conf` 에 nofile 추가 |
| `cpufreq` governor | `performance` | `sudo cpupower frequency-set -g performance` |

---

## 6. Run (on‑demand 운영)

```bash
# 상시: 역할별 대표 1개 (병렬 인스턴스 없음)
bash scripts/start_all.sh            # parser + worker1 + coder1

# on‑demand: 추론가(Reasoner) 필요 시
bash scripts/up.sh reasoner

# 14B 단독 (상호배타): setter 또는 judge 둘 중 하나만
bash scripts/start_heavy.sh setter
bash scripts/start_heavy.sh judge

# 확인
ps -eo pid,rss,args | grep llama-server | grep -v grep
```

---

## 7. Benchmark (sanity check)

```bash
time curl -s -X POST http://127.0.0.1:8081/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"parser","prompt":"1+1=","max_tokens":64,"temperature":0,"stream":false}'
```

예상: 7B 기준 **~7–9 tok/s** (60–80ms/tok). 14B 는 **~4–5 tok/s**.

---

## 8. Common pitfalls

| 증상 | 원인 | 해결 |
|------|------|------|
| Segfault on start | 잘못된 `-march` | `-march=native`/`znver5` 로 재빌드 |
| 전체 코어 100% | `THREADS` 를 16 으로 설정 | 8 로 |
| OOM / 스왑 | 14B 를 setter+judge 동시 로드 | `start_heavy.sh` 로 상호배타 운용 |
| No output | KV 양자화 미지원 빌드 | `GGML_AVX512=ON` 재빌드 또는 `KV_CACHE` 해제 |

---

## 9. Checklist

- [ ] `-march=native`(+AVX‑512) 로 빌드
- [ ] 상시는 parser+worker1+coder1 만 (start_all.sh)
- [ ] 14B 는 `start_heavy.sh` 로 상호배타
- [ ] `vm.swappiness=1`, governor=performance
- [ ] 벤치로 7B 7–9, 14B 4–5 tok/s 확인
