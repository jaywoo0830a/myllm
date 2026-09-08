# myLLM – Bare‑metal server setup guide

The scripts in this directory start a Mistral‑Small‑24B‑Instruct‑2501 model using `llama.cpp`'s `llama‑server`. The server exposes an OpenAI‑compatible API on port 8081.

## Prerequisites

- Ubuntu 22.04 or later
- AMD 9700X (or comparable 8‑core CPU) with 64 GB RAM
- `git`, `bash`, `curl`, `aria2` (optional for parallel download)

## Setup steps

```bash
git clone <repo‑url> myllm && cd myllm/server
cp config/env.example config/env
cp config/models/mistral-large.env.example config/models/mistral-large.env
bash scripts/setup_llamacpp.sh          # builds with -march=znver3 and AVX‑512
bash scripts/download.sh mistral-large    # download GGUF (~16 GB)
bash scripts/up.sh mistral-large          # starts server with THREADS=8 & KV_CACHE=q8_0
bash scripts/test_server.sh mistral-large
```

## Helper scripts (tuned)

- `init.sh` – creates output directory, loads env, sets `THREADS=8` and `KV_CACHE="q8_0"`.
- `up.sh` – starts the server in background with the same tuning.
- `down.sh` – stops the server.
- `log.sh` – view recent logs.

All scripts are in English and contain no Korean text.

## Systemd service (optional)

```bash
bash scripts/install_models.sh   # enable and start systemd unit
sudo systemctl enable --now myllm-llama@mistral-large
```

## Firewall

```bash
sudo ufw allow 8081/tcp
```

## Performance tuning

For detailed build flags, thread settings, KV‑Cache configuration, and benchmark steps, refer to `server/scripts/performance_tuning.md`.

## Client side

See the top‑level `README.md` for client configuration instructions.