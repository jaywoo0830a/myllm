# myLLM — Local Qwen Serving Plan (CPU) — Client/Server Split

## 목표
**Qwen3-Coder-30B-A3B-Instruct Q4_K_M** (MoE) 를 **별도 베어메탈 서버**(9700X / 64GB RAM, Ubuntu, GPU 없음)에서
`llama.cpp llama-server`로 OpenAI 호환 API 서빙하고,
**이 워크스페이스(별도 클라이언트 머신)의 VS Code Continue.dev** 가 그 API를 원격(포트 8080)으로 호출한다.

> ⚠️ 이 워크스페이스는 **클라이언트/설정 레포**다. 추론은 원격 베어메탈에서 실행된다.

## 실제 모델 사실 (2026-09 검증)
- **GGUF 저장소(사용자 선택): `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`** (imatrix, apache-2.0).
  - 정확한 GGUF 파일: **`Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf`** (≈18.6 GB / 17.3 GiB).
- 베이스: `Qwen/Qwen3-Coder-30B-A3B-Instruct`. **MoE** — 총 ~30.5B 지만 토큰당 활성 **~3B** (128 experts, 8/token).
- arch = **`qwen3moe`** → llama.cpp에서 **안정(first-class)** 지원 (dense 27B hybrid `qwen35`와 달리 우려 없음).
- 컨텍스트: 네이티브 **262144 (256K)**. CPU + GQA(KV 헤드 4)로 KV 부담 작음 — 64GB에서 넉넉. 캡은 `--ctx-size`(기본 32768).
- 토큰/템플릿: ChatML `<|im_start|>/<|im_end|>` + `<think>` 지원, tool-calling 포함. **thinking 강제 안 함**(Instruct).
- **코딩 특화** → Continue 의 채팅/편집(edit/apply)에 적합. FIM 탭자동완성 아님.

## 예상 속도 (서버 CPU) — dense 대비 크게 개선
- Q4_K_M 18.6GB 전량 RAM 로드. 하지만 **활성 ~3B 만 계산** → 9700X 8코어에서
  dense 27B 의 3–6 tok/s 대비 **몇 배 빠른 디코드** 예상 (보편적으로 ~15–30 tok/s대 추정, 실측 필요).
- 시스템/문서 스캔 포함 프롬프트 처리도 배치로 개선 가능. 64GB RAM 여유.

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
   llama-server (llama.cpp)  ── GGUF 를 RAM에 로드 (MoE, 토큰당 활성 ~3B)
      GGUF: Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf (~18.6GB)
```

## 구성 요소 / 산출물 (이 레포에 정리)
- **서버 측** (베어메탈 Ubuntu에서 실행할 자산)
  1. `llama.cpp` 빌드 스크립트 (Zen5 AVX-512, 최신 릴리즈 — arch `qwen3moe` 로드)
  2. GGUF 다운로드 스크립트 (HuggingFace)
  3. `llama-server` 실행 스크립트 + **systemd 유닛** (재부팅 자동 기동)
  4. 스모크 테스트 curl 스크립트
- **클라이언트 측** (이 워크스페이스)
  5. Continue.dev `config.yaml` 템플릿 (`apiBase: http://<서버IP>:8080/v1`)
- `README.md` : 설치/실행/문제해결 안내

## 구현 단계
- [ ] Step 1 (서버·본 워크스페이스): GGUF 파일 확정 (user 선택한 unsloth Qwen3-Coder repo 사용)
- [ ] Step 2 (서버): llama.cpp 설치·빌드 (AVX-512, 최신 — arch `qwen3moe` 로드)
- [ ] Step 3 (서버): GGUF 다운로드 + llama-server 스모크 테스트 (curl)
- [ ] Step 4 (서버): systemd 유닛 등록 · 재부팅 대응 · 방화벽 8080 허용
- [ ] Step 5 (본 워크스페이스): Continue.dev config.yaml 로 서버 연결, 채팅/편집 동작 확인
- [ ] Step 6: README / 문서 마무리, git 커밋

## 미확인/추가 재확인
- `qwen3moe` arch 는 llama.cpp 안정 지원이나, **정확한 Q4_K_M 파일 크기/다운로드 확인**은 서버에서 수행.
- `--no-think`/thinking 제어 문법은 해당 llama.cpp 버전에서 확인 (coder 용 chain-of-thought 억제 참고).
- CPU 스레드/배치 튜닝은 9700X 실측 필요 (`-t`, `-b`).
- 원격 접근 시 방화벽/포트(8080) 개방, (원하면 추후) 인증 프록시 추가 여부.

