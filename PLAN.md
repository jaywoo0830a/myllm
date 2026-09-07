# myLLM — Local Multi-Model Serving Plan (CPU) — Client/Server Split

## 목표
**두 모델을 동시에** **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`(모델별 프로세스·포트)로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 두 API를 원격 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 현재 모델 (2개, config/models/*.env)
| slug | GGUF | 크기 | 포트 | 용도 |
|------|------|------|------|------|
| `qwen3-14b` | `Qwen/Qwen3-14B-GGUF` `Qwen3-14B-Q4_K_M.gguf` | ~9.3GB | 8081 | 메인: 코딩 편집/reasoning |
| `deepseek-1.5b` | `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF` `...-Q4_K_M.gguf` | ~1.0GB | 8080 | 보조: 빠른 채팅 |

## 실제 모델 사실 (2026-09 검증)

### Qwen3-14B (qwen3-14b)
- `Qwen/Qwen3-14B` 공식 GGUF 존재(`qwen3` arch, dense ~14.77B, NOT MoE). llama.cpp 표준/안정.
- 컨텍스트 네이티브 **40960**. ChatML-like + `<think>`(thinking 가능, enable_thinking 토글).
- CPU 8코어에서 dense 14B Q4_K_M 는 보통 ~6-10 tok/s 추정(실측 필요). THREADS 8 배정.

### DeepSeek-R1-Distill-Qwen-1.5B (deepseek-1.5b)
- `deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B`, GGUF `unsloth` repo, arch `qwen2`(표준/안정). ~1.5B dense reasoning.
- 컨텍스트 네이티브 **131072**. DeepSeek 템플릿(`<｜User｜>`/`<｜Assistant｜>`/`<think>`).
- 가벼워 매우 빠른 응답(수십 tok/s 추정). THREADS 4 배정.

## 예상 속도/운영 (서버 CPU)
- 8코어를 두 모델이 스레드로 분배(예: 14B=8, 1.5B=4) → 동시 요청시 성능 분산.
- RAM 64GB 여유 (9.3+1.0GB + KV 오버헤드) 충분.
- reasoning(`<think>`) 토큰 때문에 체감 응답이 길어질 수 있음 — 프로파일 `NO_THINK` 로 억제 가능.

## 아키텍처 (2대 머신)

```
[클라이언트 머신 — 이 워크스페이스]
   VS Code
     └ Continue.dev (config.yaml)
          │   OpenAI 호환 /v1
          ├─ http://<서버IP>:8081/v1  (qwen3-14b 메인)
          └─ http://<서버IP>:8080/v1  (deepseek-1.5b 보조)
          │   http://<서버IP>:8080/v1      (기본 포트 8080, 인증 없음)
[서버 IP:8080 ── LAN/네트워크]
   ▼
[베어메탈 서버 9700X · 64GB · Ubuntu · GPU 없음]
   llama-server x N (모델 프로파일 각 1 프로세스, 스레드 분할)
      └ qwen3-14b    : Qwen3-14B-Q4_K_M.gguf (~9.3GB) @8081
      └ deepseek-1.5b: DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf (~1.0GB) @8080
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
- [x] 모델 프로파일 2종(qwen3-14b, deepseek-1.5b) + 공통 env 분리
- [x] 멀티모델 스크립트 일원화(lib/download/run_one/run_all/install_models/test)
- [x] systemd 템플릿 `myllm-llama@<slug>.service`
- [x] Continue config 2 모델(메인 14B + 보조 1.5B) 템플릿
- [x] 구형 단일-모델 스크립트 삭제 (02/03/05, myllm-llama.service)
- [ ] 서버에서 실제 실행 & 스모크 & Continue 연결 확인 (이 워크스페이스 밖)

## 미확인/추가 재확인
- 두 llama.cpp 프로세스가 8코어를 나눠 쓸 때 실측 성능 — `THREADS` 튜닝.
- Qwen3-14B 의 thinking 억제/`reasoning-format` 문법은 해당 llama.cpp 버전 확인.
- 각 모델 `Q4_K_M` 실제 크기/로드 확인은 서버에서 `ls -l` 및 로그로.
- 방화벽 8080·8081 개방, (원하면 추후) 인증 프록시.

