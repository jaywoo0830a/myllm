# myLLM — Local Single-Model Serving Plan (CPU) — Client/Server Split

## 목표
**DeepSeek-R1-Distill-Qwen-14B (단일)** 을 **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 그 API(포트 8081)를 원격 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 현재 모델 (단일, config/models/deepseek-r1-14b.env)
| slug | GGUF | 크기 | 포트 |
|------|------|------|------|
| `deepseek-r1-14b` | `unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF` `...-Q4_K_M.gguf` | ~8.9GB | 8081 |

## 실제 모델 사실 (2026-09 검증)
- `deepseek-ai/DeepSeek-R1-Distill-Qwen-14B`, GGUF `unsloth` repo, arch **`qwen2`**(안정).
- **dense ~14.77B** — NOT MoE. 컨텍스트 네이티브 131072.
- R1 템플릿 + **항상 `<think>` 먼저, 억제 불가**(NO_THINK 무효).
- **속도**: dense 14B Q4 = 대역폭 병목이지만 32B 무게의 절반 이하(~8.9GB) → 9700X CPU
  에서 약 **6-7 t/s** 예상 (32B 실측 ~2 t/s의 약 2-2.5배). 여전히 reasoning CoT는 느림.

## 예상 속도/운영 (서버 CPU)
- 단일 모델 → 8코어 전부/대역폭 전용 (THREADS=8 물리코어, SMT 16은 손해).
- KV_CACHE q8_0 → 소폭 개선. 긴 문서는 `overnight_gen.sh`(백그라운드) 추천.
- reasoning(`<think>`)이 길면 체감 대기 큼 — 필요 시 클라이언트에서 `</think>` 뒤만 표시.

## 아키텍처 (2대 머신)

```
[클라이언트 머신 — 이 워크스페이스]
   VS Code
     └ Continue.dev (config.yaml)
          │   OpenAI 호환 /v1
          └─ http://<서버IP>:8081/v1  (deepseek-r1-14b)
[서버 IP:8081 ── LAN/네트워크]
   ▼
[베어메탈 서버 9700X · 64GB · Ubuntu · GPU 없음]
   llama-server x1  (deepseek-r1-14b, full 8코어)
      └ DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf (~8.9GB) @8081
```

## 구성 요소 / 산출물 (이 레포에 정리)
- **server/scripts/**
  - `lib.sh` 공통 헬퍼, `01_setup_llamacpp.sh` 빌드
  - `download.sh <slug>` GGUF 다운로드, `run_one.sh <slug>` 서버 실행
  - `run_all.sh` 백그라운드 테스트, `test_server.sh <slug>` 스모크
  - `install_models.sh` systemd 템플릿 등록, `06_set_hf_token.sh` 토큰
  - `overnight_gen.sh` 밤샘 장문 생성(파일 저장)
- **server/config/models/deepseek-r1-14b.env(.example)** 모델 프로파일 (단일)
- **server/systemd/myllm-llama@.service** systemd 템플릿
- **client/continue/config.yaml.example** 단일 모델 apiBase 템플릿

## 구현 단계 (완료/남음)
- [x] 단일 모델 프로파일(deepseek-r1-14b) + 공통 env 분리 (deepseek-1.5b 제거)
- [x] 스크립트 일원화(lib/download/run_one/run_all/install_models/test) + overnight_gen
- [x] systemd 템플릿 `myllm-llama@<slug>.service`
- [x] Continue config 단일 모델 템플릿
- [x] KV 캐시 q8_0 튜닝 지원
- [ ] 서버에서 실제 실행 & 스모크 & Continue 연결 확인 (이 워크스페이스 밖)

## 미확인/추가 재확인
- 14B Q4 실제 크기·로드·t/s 는 서버에서 `ls -l` 및 로그로 확정.
- KV_CACHE q8_0 문법이 세션 llama.cpp 에서 유효한지(시작 에러 시 빈 값으로).
- 방화벽 8081 개방, (원하면 추후) 인증 프록시.


