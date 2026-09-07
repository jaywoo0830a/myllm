# myLLM — Local Model Serving Plan (CPU) — Client/Server Split

## 목표
**LiquidAI LFM2.5-1.2B-Instruct Q4_K_M** (1.2B, 속도 우선) 를 **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 그 API를 원격(포트 8080)으로 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 실제 모델 사실 (2026-09 검증)
- **GGUF 저장소(사용자 선택): `LiquidAI/LFM2.5-1.2B-Instruct-GGUF`** (공식 llama.cpp GGUF).
  - GGUF 파일: **`LFM2.5-1.2B-Instruct-Q4_K_M.gguf`** (≈0.7 GB, ~1.17B 파라미터).
- 베이스: `LiquidAI/LFM2.5-1.2B-Instruct`. **1.2B dense/hybrid** (conv + full_attention 혼합, 16 레이어).
  - arch = **`lfm2`** — llama.cpp 가 `src/models/lfm2.cpp` + `conversion/lfm2.py` 로 **지원**(공식 GGUF 존재).
  - conv/recurrent('liquid') 계열이라 표준 dense arch보다 build-maturity 민감 — 로드 시 실측 확인 권장.
- 컨텍스트: 네이티브 **128000**. 1.2B 라 KV 부담 작음. 캡은 `--ctx-size`(기본 32768).
- 토큰/템플릿: ChatML `<|im_start|>/<|im_end|>`(eos). **thinking(<think>) 모델**.
- 품질보다 속도를 우선한 선택 — 9700X CPU 에서 상당히 많은 tok/s (실측 필요).

## 예상 속도 (서버 CPU) — 매우 빠름 (속도 우선)
- 1.2B + Q4 ≈ 0.7GB. 9700X 8코어 CPU 로 디코드가 아주 가벼워,
  기존 27B/30B 계획보다 훨씬 빠른 응답(수십 tok/s대) 예상, 메모리 부담 거의 없음.

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
   llama-server (llama.cpp)  ── GGUF 를 RAM에 로드 (1.2B, 매우 경량)
      GGUF: LFM2.5-1.2B-Instruct-Q4_K_M.gguf (~0.7GB)
```

## 구성 요소 / 산출물 (이 레포에 정리)
- **서버 측** (베어메탈 Ubuntu에서 실행할 자산)
  1. `llama.cpp` 빌드 스크립트 (Zen5 AVX-512, 최신 릴리즈 — arch `lfm2`)
  2. GGUF 다운로드 스크립트 (HuggingFace)
  3. `llama-server` 실행 스크립트 + **systemd 유닛** (재부팅 자동 기동)
  4. 스모크 테스트 curl 스크립트
- **클라이언트 측** (이 워크스페이스)
  5. Continue.dev `config.yaml` 템플릿 (`apiBase: http://<서버IP>:8080/v1`)
- `README.md` : 설치/실행/문제해결 안내

## 구현 단계 (완료/남음)
- [x] Step 1: GGUF 파일 확정 — `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` 의 `LFM2.5-1.2B-Instruct-Q4_K_M.gguf`
- [x] Step 2: llama.cpp 빌드 스크립트 (AVX-512, master — arch `lfm2` 로드)
- [x] Step 3: GGUF 다운로드(토큰/이어받기) + llama-server 실행 + curl 스모크 스크립트
- [x] Step 4: systemd 유닛/등록 스크립트 + 방화벽 안내
- [x] Step 5: Continue.dev config.yaml 템플릿
- [ ] 서버에서 실제 실행 & 스모크 & Continue 연결 확인 (이 워크스페이스 밖 작업)

## 미확인/추가 재확인
- `lfm2`(conv/liquid hybrid) arch 는 llama.cpp 지원이나 **build-maturity 민감** — 서버 로드 시 확인.
- **Q4_K_M 정확 크기**(≈0.7GB 추정)는 서버에서 `ls -l` 로 확정.
- thinking(\<think>) 모델 — llama.cpp 버전별 억제 문법, CPU 스레드/배치 튜닝은 9700X 실측.
- 원격 접근 방화벽/포트(8080) 개방, (원하면 추후) 인증 프록시.

