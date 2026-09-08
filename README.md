# myLLM

Mistral‑Small‑24B‑Instruct‑2501 serving on a bare‑metal CPU server (AMD 9700X, 64 GB RAM, Ubuntu). The server runs `llama.cpp`'s `llama‑server` exposing an OpenAI‑compatible API on port 8081. The client side uses VS Code Continue.dev to call the API.

## Model profile
- **Slug:** `mistral-large`
- **GGUF:** `Mistral‑Small‑24B‑Instruct‑2501‑Q4_K_M.gguf` (~16 GB)
- **Port:** 8081

## Quick start (server)

```bash
git clone <repo‑url> myllm && cd myllm/server
cp config/env.example config/env
cp config/models/mistral-large.env.example config/models/mistral-large.env
bash scripts/setup_llamacpp.sh          # build llama‑server with AVX‑512 optimisations
bash scripts/download.sh mistral-large    # download GGUF
bash scripts/up.sh mistral-large          # starts server with tuned THREADS=8 & KV_CACHE=q8_0
bash scripts/test_server.sh mistral-large
```

## Helper scripts (all tuned)

- `init.sh` – creates output directory, loads environment, and sets `THREADS=8` / `KV_CACHE="q8_0"`.
- `up.sh` – starts the server in background with the same tuning variables.
- `down.sh` – stops the server using the stored PID.
- `log.sh` – tails the latest log file.

All scripts are located in `server/scripts/` and contain no Korean text.

## Client configuration

```bash
cp client/continue/config.yaml.example ~/.continue/config.yaml
# edit ~/.continue/config.yaml → set `apiBase: http://<SERVER_IP>:8081/v1`
```

## Performance tuning

See `server/scripts/performance_tuning.md` for detailed build flags, system‑wide settings, and benchmark instructions for the AMD 9700X + DDR5 64 GB platform.

## License

MIT