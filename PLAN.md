# myLLM — Local Qwen Serving Plan (CPU) — Client/Server Split

## 목표
`Qwen3.5-27B`(이른바 "Dense", 실제로는 hybrid attention 모델) Q4_K_M을 **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 그 API를 원격(포트 8080)으로 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 실제 모델 사실 (2026-09 검증)
- 정식 레포명: **`Qwen/Qwen3.5-27B`** (「Qwen3.5-27B-Dense」라 불리는 27B 빌리는 MoE가 아님). Apache-2.0, 비게이트.
- **hybrid attention 모델** (Gated Delta Network 계열): 레이어 3:1 비율 `linear_attention`/`full_attention`, `architectures=["Qwen3_5ForConditionalGeneration"]`, GGUF arch 문자열은 **`qwen35`**.
- 파라미터 ≈ **27.78B** (전부 활성 — MoE 아님). 멀티모달 구성이나 텍스트 채팅만 쓰면 `mmproj-*.gguf` 불필요.
- 컨텍스트: 네이티브 **256K (262144)** — CPU라서 `--ctx-size`를 훨씬 낮게 캡 필요.
- 토큰: ChatML `<|im_start|>/<|im_end|>` + **`<think>`/`</think>` 사고 구분자**. llama.cpp에선 **`--jinja --no-think`** 권장(긴 chain-of-thought로 CPU 지연 폭증 방지).
- GGUF는 공식 없음 → 커뮤니티: **`unsloth/Qwen3.5-27B-GGUF`** 또는 **`mradermacher/Qwen3.5-27B-GGUF`**.
  Q4_K_M ≈ **16.6 GB** (Q4_K_S 15.7, IQ4_XS 14.9, Q5_K_M 19.5).

## 아키텍처 (2대 머신)

```
[클라이언트 머신 — 이 워크스페이스]
   VS Code
     └ Continue.dev (config.yaml)
          │   OpenAI 호환 /v1/chat/completions
          │   http://<서버IP>:8080/v1      (기본 포트 8080, 인증 없음)
[서버 IP:8080 ── LAN/네트워크]
   ▼
[베어메탈 서버 9700X · 64GB · Ubuntu · GPU 없음]
   llama-server (llama.cpp)  ── GGUF 를 RAM에 로드, --n-gpu-layers 0
      GGUF: Qwen3.5-27B.Q4_K_M.gguf (~16.6GB)
```

## 예상 속도 (서버 CPU)
- Q4_K_M 16.6GB, 9700X 8코어: RAM 대역폭이 병목 → 예상 **3–6 tok/s**.
- 짧은 채팅/요약/편집 제안용. FIM 자동완성이나 매우 긴 응답엔 부적합.
- 64GB면 모델 + 큰 KV 캐시 여유 있음. `--ctx-size`는 예: 8192–16384 로 적당히.

## 구성 요소 / 산출물 (이 레포에 정리)
- **서버 측** (베어메탈 Ubuntu에서 실행할 자산)
  1. `llama.cpp` 빌드 스크립트 (Zen5 AVX-512, 최신 릴리즈 — arch `qwen35` 로드 가능해야 함)
  2. GGUF 다운로드 스크립트 (HuggingFace)
  3. `llama-server` 실행 스크립트 + **systemd 유닛** (재부팅 자동 기동)
  4. 스모크 테스트 curl 스크립트
- **클라이언트 측** (이 워크스페이스)
  5. Continue.dev `config.yaml` 템플릿 (`apiBase: http://<서버IP>:8080/v1`)
- `README.md` : 설치/실행/문제해결 안내

## 구현 단계
- [ ] Step 1 (서버·본 워크스페이스): 모델/GGUF 저장소 확정 (unsloth vs mradermacher, imatrix 여부)
- [ ] Step 2 (서버): llama.cpp 설치·빌드 (AVX-512, 최신 — qwen35 arch 지원 확인)
- [ ] Step 3 (서버): GGUF 다운로드 + llama-server 스모크 테스트 (curl)
- [ ] Step 4 (서버): systemd 유닛 등록 · 재부팅 대응 · 방화벽 8080 허용
- [ ] Step 5 (본 워크스페이스): Continue.dev config.yaml 로 서버 연결, 채팅 동작 확인
- [ ] Step 6: README / 문서 마무리, git 커밋

## 미확인/추가 재확인
- llama.cpp 의 Qwen3.5(hybrid `qwen35`) arch 지원 성숙도 — 빌드 시 로드 테스트로 확인 필요.
- `--no-think` 플래그의 정확한 문법/지원 여부를 해당 llama.cpp 버전에서 확인.
- 원격 접근 시 방화벽/포트(8080) 개방, (원하면 추후) 인증 프록시 추가 여부.
