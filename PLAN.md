# myLLM — Local Multi-Model Serving Plan (CPU) — Client/Server Split

## 목표
**두 모델을 동시에** **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`(모델별 프로세스·포트)로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 두 API를 원격 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 현재 모델 (2개, config/models/*.env)
| slug | GGUF | 크기 | 포트 | 용도 |
|------|------|------|------|------|
| `deepseek-r1-32b` | `unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF` `...-Q4_K_M.gguf` | ~19.9GB | 8081 | 메인: 무거운 reasoning |
| `deepseek-1.5b` | `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF` `...-Q4_K_M.gguf` | ~1.0GB | 8080 | 보조: 빠른 채팅 |

## 실제 모델 사실 (2026-09 검증)

### DeepSeek-R1-Distill-Qwen-32B (deepseek-r1-32b) — 메인
- GGUF: `unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF` `DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf` (19.9GB).
  (공식 deepseek GGUF 리포 non-public 401 → 커뮤니티 unsloth/bartowski 동일 크기)
- `deepseek-ai/DeepSeek-R1-Distill-Qwen-32B`, arch **`qwen2`**(안정), **dense ~32.8B**(64 layers, GQA).
- 컨텍스트 네이티브 **131072**. R1 템플릿 + **항상 `<think>` 먼저, 억제 불가**(NO_THINK 무효).
- **속도 경고**: dense 32B Q4는 대역폭 병목 → 9700X CPU에서 추정 **~2.5-4 t/s** (14B의 절반 수준).
  `<think>` CoT가 길면 답 하나에 수 분. RAM 64GB 에는 fit(총 ~27-31GB).

### DeepSeek-R1-Distill-Qwen-1.5B (deepseek-1.5b)
- `deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B`, GGUF `unsloth` repo, arch `qwen2`(표준/안정). ~1.5B dense reasoning.
- 컨텍스트 네이티브 **131072**. DeepSeek 템플릿(`<｜User｜>`/`<｜Assistant｜>`/`<think>`).
- 가벼워 매우 빠른 응답(수십 tok/s 추정). THREADS 4 배정.

## 예상 속도/운영 (서버 CPU)
- 8코어를 두 모델이 스레드로 분배(예: 32B=8, 1.5B=4). 동시 요청 시 대역폭/코어 공유로 속도 추가 저하.
- **32B 와 1.5B 동시 구동은 9700X에 부담** — 32B 큰 답변 요청 시 1.5B 쪽 영향 큼. 필요 시 1.5B 중지 권장.
- reasoning(`<think>`) 토큰 길이 → 체감 대기 매우 김. 클라이언트에서 `</think>` 뒤만 표시 권장.

## 아키텍처 (2대 머신)

```
[클라이언트 머신 — 이 워크스페이스]
   VS Code
     └ Continue.dev (config.yaml)
          │   OpenAI 호환 /v1
          ├─ http://<서버IP>:8081/v1  (deepseek-r1-32b 메인)
          └─ http://<서버IP>:8080/v1  (deepseek-1.5b 보조)
[서버 IP:8080/8081 ── LAN/네트워크]
   ▼
[베어메탈 서버 9700X · 64GB · Ubuntu · GPU 없음]
   llama-server x N (모델 프로파일 각 1 프로세스, 스레드 분할)
      └ deepseek-r1-32b: DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf (~19.9GB) @8081
      └ deepseek-1.5b  : DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf (~1.0GB) @8080
```

## 구성 요소 / 산출물 (이 레포에 정리)
- **server/scripts/**
  - `lib.sh` 공통 헬퍼, `01_setup_llamacpp.sh` 빌드
  - `download.sh <slug>` GGUF 다운로드, `run_one.sh <slug>` 서버 실행
  - `run_all.sh` 다중 백그라운드 테스트, `test_server.sh <slug>` 스모크
  - `install_models.sh` systemd 템플릿 등록, `06_set_hf_token.sh` 토큰
- **server/config/models/<slug>.env(.example)** 모델 프로파일
- **server/systemd/myllm-llama@.service** systemd 템플릿
- **client/continue/config.yaml.example** 두 모델 apiBase 템플릿

## 구현 단계 (완료/남음)
- [x] 모델 프로파일 2종(deepseek-r1-32b, deepseek-1.5b) + 공통 env 분리
- [x] 멀티모델 스크립트 일원화(lib/download/run_one/run_all/install_models/test)
- [x] systemd 템플릿 `myllm-llama@<slug>.service`
- [x] Continue config 2 모델(메인 32B + 보조 1.5B) 템플릿
- [x] 구형 단일-모델 스크립트 삭제 (02/03/05, myllm-llama.service)
- [ ] 서버에서 실제 실행 & 스모크 & Continue 연결 확인 (이 워크스페이스 밖)

## 미확인/추가 재확인
- 두 llama.cpp 프로세스가 8코어/대역폭을 나눠 쓸 때 실측 성능 — `THREADS` 튜닝.
- 32B Q4 실제 크기·로드·t/s 는 서버에서 `ls -l` 및 로그로 확정.
- 방화벽 8080·8081 개방, (원하면 추후) 인증 프록시.

