# myLLM – Multi‑Agent Local AI System

This repository now implements the **multi‑agent architecture** described in `PLAN.md`. It supports the following model roles on a single 64 GB RAM server, loading models on‑demand:

| Role | Model | Approx. Size | Instances |
|------|-------|--------------|-----------|
| **Parser** | Qwen2.5‑7B‑Instruct (Q4_K_M) | ~5 GB | 1 |
| **Worker** | Phi‑3.5‑mini‑instruct (3.8 B) | ~3 GB | 3‑4 |
| **Coder** | Qwen2.5‑Coder‑7B‑Instruct (Q4_K_M) | ~5 GB | 2 |
| **Reasoner** | DeepSeek‑R1‑Distill‑Qwen‑7B | ~5 GB | 1 |
| **Embedding** | bge‑small‑en‑v1.5 | ~0.5 GB | 1 (always loaded) |

The server now ships **environment files** for each model under `server/config/models/`. Use the existing `up.sh` script to start any model:

```bash
# Example: start the parser
bash server/scripts/up.sh parser
```

To start **all** models at once (useful for development), run:

```bash
bash server/scripts/start_all.sh
```

## New Files
- `model_registry.py` – Python dictionary describing the model registry (useful for orchestration code).
- `server/config/models/*.env` – Environment files for each model instance (parser, workers, coders, reasoner).
- `server/scripts/start_all.sh` – Convenience script to launch all defined models.

## How It Works
1. **Base environment** (`server/config/env`) defines shared variables (MODEL_DIR, LLAMA_CPP_DIR, etc.).
2. Each model has its own `.env` file with a unique `LLAMA_PORT` and `MODEL_NAME`.
3. `up.sh` loads the base env, then the model‑specific env via `load_model_env`, and starts `llama-server` in the background.
4. `start_all.sh` iterates over the model slugs defined in the script and calls `up.sh` for each.

## Next Steps
- Implement a **FastAPI orchestrator** that watches a request queue, loads/unloads models on demand, and routes work to the appropriate model server.
- Add **RAG** pipelines (FAISS/Chroma) and integrate the embedding model.
- Update the client configuration to point to the appropriate model endpoints.

---

For detailed setup instructions, see `server/README.md`.
