# myLLM – Bare‑metal server setup guide

The scripts in this directory start **any** model defined in `server/config/models/*.env` using `llama.cpp`'s `llama‑server`. Each model runs on its own port and can be started independently.

## Prerequisites

- Ubuntu 22.04 or later
- AMD 9700X (or comparable 8‑core CPU) with 64 GB RAM
- `git`, `bash`, `curl`, `aria2` (optional for parallel download)

## Setup steps

```bash
git clone <repo‑url> myllm && cd myllm/server
cp config/env.example config/env
# Copy the example env for each model you want to run (e.g., parser, worker1, coder1, etc.)
# Example for the parser model:
cp config/models/parser.env.example config/models/parser.env
# Build llama‑cpp server
bash scripts/setup_llamacpp.sh          # builds with -march=native(Zen5) and AVX‑512
# Download the model GGUF files (replace <model> with the slug, e.g., parser)
bash scripts/download.sh parser
# NOTE: reasoner(DeepSeek‑R1‑Distill‑Qwen‑7B) 는 unsloth/DeepSeek‑R1‑Distill‑Qwen‑7B‑GGUF
#       에서 GGUF 를 받을 수 있다 (env 의 HF_REPO 참조).
bash scripts/up.sh reasoner
# Start the model server
bash scripts/up.sh parser
```

## Helper scripts (tuned)

- `init.sh` – creates output directory, loads env, sets `THREADS=8` and `KV_CACHE="q8_0"`.
- `up.sh` – starts the server in background with the same tuning variables.
- `down.sh` – stops the server.
- `log.sh` – view recent logs.

All scripts are in English and contain no Korean text.

## Systemd service (optional)

```bash
bash scripts/install_models.sh   # enable and start systemd unit for all configured models
sudo systemctl enable --now myllm-llama@.service
```

## Firewall

Open the ports for the models you plan to run (e.g., 8081‑8088).

```bash
sudo ufw allow 8081:8088/tcp
```

## Performance tuning

For detailed build flags, thread settings, KV‑Cache configuration, and benchmark steps, refer to `server/scripts/performance_tuning.md`.

## Client side

See the top‑level `README.md` for client configuration instructions.
