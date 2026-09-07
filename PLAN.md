# myLLM — Local Model Serving Plan (CPU) — Client/Server Split

## 목표
**DeepSeek-R1-Distill-Qwen-1.5B Q4_K_M** (1.5B, 속도 우선) 를 **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 그 API를 원격(포트 8080)으로 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 실제 모델 사실 (2026-09 검증)
- **GGUF 저장소(사용자 선택): `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF`**.
  - GGUF 파일: **`DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf`** (≈1.0 GB, ~1.5B 파라미터).
- 베이스: `deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B`. **1.5B dense (Qwen2 계열)** reasoning 모델.
  - arch = **`qwen2`** — llama.cpp **표준/매우 안정** 지원 (새 아키텍처 우려 없음).
- 컨텍스트: 네이티브 **131072 (128K)**. 캡은 `--ctx-size`(기본 32768).
- 토큰/템플릿: **DeepSeek 형식** — bos=`<｜begin▁of▁sentence｜>`, `<｜User｜>`/`<｜Assistant｜>`, eos=`<｜end▁of▁sentence｜>`, reasoning `<think>…</think>`.
  - **rethinking(reasoning) 모델**: 답변 전 항상 `<think>` 를 긴 호흡으로 출력 → 응답 시간이 길어질 수 있음.
- 속도 우선 선택 — 1.5B + Q4 ≈ 1GB. 9700X CPU 에서 매우 높은 tok/s (실측 필요).

## 예상 속도 (서버 CPU) — 빠름 (속도 우선)
- 1.5B + Q4 ≈ 1GB. 9700X 8코어 CPU로 디코드가 가벼워 기존 27B/30B 계획보다 훨씬 빠른 응답 예상.
- 단, reasoning(`<think>`) 토큰이 항상 생성되므로 체감은 일반 채팅보다 길어질 수 있음 — 필요 시 억제 옵션.

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
   llama-server (llama.cpp)  ── GGUF 를 RAM에 로드 (1.5B, 경량)
      GGUF: DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf (~1.0GB)
```

## 구성 요소 / 산출물 (이 레포에 정리)
- **서버 측** (베어메탈 Ubuntu에서 실행할 자산)
  1. `llama.cpp` 빌드 스크립트 (Zen5 AVX-512, 최신 릴리즈 — arch `qwen2`)
  2. GGUF 다운로드 스크립트 (HuggingFace)
  3. `llama-server` 실행 스크립트 + **systemd 유닛** (재부팅 자동 기동)
  4. 스모크 테스트 curl 스크립트
- **클라이언트 측** (이 워크스페이스)
  5. Continue.dev `config.yaml` 템플릿 (`apiBase: http://<서버IP>:8080/v1`)
- `README.md` : 설치/실행/문제해결 안내

## 구현 단계 (완료/남음)
- [x] Step 1: GGUF 파일 확정 — `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF` 의 `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf`
- [x] Step 2: llama.cpp 빌드 스크립트 (AVX-512, master — arch `qwen2`)
- [x] Step 3: GGUF 다운로드(토큰/이어받기) + llama-server 실행 + curl 스모크 스크립트
- [x] Step 4: systemd 유닛/등록 스크립트 + 방화벽 안내
- [x] Step 5: Continue.dev config.yaml 템플릿
- [ ] 서버에서 실제 실행 & 스모크 & Continue 연결 확인 (이 워크스페이스 밖 작업)

## 미확인/추가 재확인
- `qwen2` arch 는 llama.cpp 표준/안정 — 아키텍처 우려 낮음. 그래도 서버 로드 확인.
- **Q4_K_M 정확 크기**(≈1.0GB 추정)는 서버에서 `ls -l` 로 확정.
- reasoning(<think>) 모델 — 억제 시 품질 저하 유의, CPU 스레드/배치 튜닝은 9700X 실측.
- 원격 접근 방화벽/포트(8080) 개방, (원하면 추후) 인증 프록시.

