# myLLM – Single‑model serving plan (CPU)

## Goal
Serve the Mistral‑Small‑24B‑Instruct‑2501 model on a bare‑metal CPU server (AMD 9700X, 64 GB RAM) using `llama.cpp`'s `llama‑server`. Provide an OpenAI‑compatible endpoint for VS Code Continue.dev.

## Model profile
- **Slug:** `mistral-large`
- **GGUF:** `Mistral‑Small‑24B‑Instruct‑2501‑Q4_K_M.gguf`
- **Port:** 8081

## Tasks
- [x] Create minimal helper scripts (`init.sh`, `up.sh`, `down.sh`, `log.sh`).
- [x] Translate all scripts to English and remove Korean text.
- [x] Remove unused scripts (install, download, run_one, run_all, overnight_gen, etc.).
- [x] Update documentation (README, server/README, PLAN) to reflect Mistral‑only setup and embed tuning.
- [x] Add missing model env and example (`mistral-large.env.example` / `mistral-large.env`).
- [x] Provide `download.sh` and `test_server.sh` helpers.
- [x] Verify no references to other models remain.
- [ ] Test end‑to‑end: start server, run `test_server.sh`, configure VS Code Continue, generate a sample completion.

## Tuning applied
- `THREADS=8` (one thread per physical core)
- `KV_CACHE="q8_0"` for KV‑Cache quantisation
- Build `llama.cpp` with `-march=znver3` and AVX‑512 enabled
- System‑wide Linux tuning (swappiness, file limits, CPU governor) – see `performance_tuning.md`

## Notes
- The server runs single‑threaded per request; use `THREADS=8` for best CPU utilisation.
- KV‑CACHE `q8_0` is enabled by default in the model env.
- No GPU is required.