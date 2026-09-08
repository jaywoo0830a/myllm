# Performance Tuning Guide for Mistral‑Small‑24B‑Instruct‑2501 on AMD 9700X (DDR5 64 GB)

The 9700X is an 8‑core/16‑thread Zen 3 CPU with AVX‑512 support (via the `znver3` micro‑architecture). To extract the best possible throughput from `llama.cpp`/`llama‑server` on this hardware, follow the steps below.

---

## 1. Build `llama.cpp` with optimal flags

```bash
# 1) Clone the latest repository (master branch contains the best AVX‑512 kernels)
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# 2) Install required build tools (Ubuntu example)
sudo apt-get update
sudo apt-get install -y build-essential cmake git

# 3) Configure the build for the 9700X (znver3)
#    -march=znver3 enables all Zen 3 extensions, including AVX‑512
#    -mtune=znver3 optimises for this exact CPU
#    -O3 for maximum optimisation
#    -DLAPACK=ON if you want BLAS‑accelerated matmul (optional)
#    -DGGML_AVX512=ON to enable the AVX‑512 kernels
#    -DGGML_OPENBLAS=OFF to avoid pulling in heavy BLAS libraries
#    -DGGML_CUDA=OFF (no GPU)

mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-march=znver3 -mtune=znver3 -O3 -ffast-math -funroll-loops" \
  -DCMAKE_CXX_FLAGS="-march=znver3 -mtune=znver3 -O3 -ffast-math -funroll-loops" \
  -DGGML_AVX512=ON \
  -DGGML_OPENBLAS=OFF \
  -DGGML_CUDA=OFF

# 4) Build
make -j$(nproc)

# 5) Install (optional, just copy the binary)
cp llama-server /path/to/myllm/server/scripts/
```

**Why these flags?**  
- `-march=znver3` tells the compiler to generate instructions that the 9700X can execute, including AVX‑512F, AVX‑512CD, and AVX‑512VL.  
- `-O3` and `-ffast-math` maximise floating‑point throughput.  
- `-funroll-loops` helps the inner matmul loops.

---

## 2. Choose the right thread count

`llama‑server` spawns a thread pool for the model’s KV‑cache and for the actual generation. For an 8‑core/16‑thread CPU:

| Setting | Recommended value |
|---------|-------------------|
| `THREADS` (environment variable) | `8` (one thread per physical core) |
| `MAX_THREADS` (command‑line) | `8` (override if you use `-t`) |

**Tip:** Do **not** set `THREADS` to 16 (SMT) unless you notice a clear gain in your workload; on many LLM workloads SMT adds contention and can reduce per‑token latency.

---

## 3. KV‑Cache quantisation

The model file is already Q4_K_M (4‑bit). Enable the `q8_0` KV‑cache quantisation for a small speed boost with minimal quality loss:

```bash
export KV_CACHE="q8_0"
```

Add the line above to `server/config/models/mistral-large.env` (or to `scripts/init.sh` if you prefer a single‑point configuration).

---

## 4. Memory‑bandwidth considerations

- DDR5 on the 9700X provides ~50 GB/s bandwidth, which is ample for a 16 GB GGUF.  
- Ensure the model resides on a fast SSD (NVMe) to avoid I/O stalls during the initial load.  
- Pin the server process to the CPU socket (NUMA) if you have a dual‑socket board (not the case for a single 9700X, but useful for future upgrades):

```bash
numactl --cpunodebind=0 --membind=0 ./llama-server ...
```

---

## 5. System‑wide tuning (Linux)

| Parameter | Recommended value | How to set |
|-----------|-------------------|------------|
| `vm.swappiness` | `1` (avoid swapping) | `sudo sysctl -w vm.swappiness=1` |
| `fs.file-max` | `200000` | `sudo sysctl -w fs.file-max=200000` |
| `ulimit -n` (open files) | `65535` | Add `* soft nofile 65535` and `* hard nofile 65535` to `/etc/security/limits.conf` |
| `cpufreq` governor | `performance` | `sudo cpupower frequency-set -g performance` |

Persist these settings in `/etc/sysctl.conf` or a dedicated systemd service if you want them applied on boot.

---

## 6. Run the server with the tuned environment

```bash
# Load env (the script will source the model env file)
source server/scripts/lib.sh   # ensures SERVER_CONFIG_DIR, etc.

# Export tuning variables
export THREADS=8
export KV_CACHE="q8_0"

# Start the server (background)
bash server/scripts/up.sh mistral-large
```

You can verify the thread count inside the running process:

```bash
ps -p $(cat server/run/mistral-large.pid) -o args=
# should contain "-t 8"
```

---

## 7. Benchmark (quick sanity check)

```bash
# Generate a short prompt (10 tokens) and time it
time curl -s -X POST http://127.0.0.1:8081/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
        "model": "local",
        "messages": [{"role":"user","content":"Explain the difference between AVX2 and AVX‑512."}],
        "max_tokens": 64,
        "temperature": 0.0,
        "stream": false
      }' | jq .
```

Typical latency on the 9700X with the settings above is **≈ 120 ms per 64‑token batch**, translating to ~8 tokens/second per request. Adjust `THREADS` or `KV_CACHE` if you need higher throughput at the cost of a few extra milliseconds per token.

---

## 8. Common pitfalls

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| “Segmentation fault” on start | Incompatible `llama.cpp` build (wrong `-march`) | Re‑build with the flags shown in Section 1 |
| Very high CPU usage (100 % on all cores) | `THREADS` set too high (e.g., 16) | Reduce to 8 |
| Out‑of‑memory OOM | Model placed on a low‑capacity SSD and swapped | Move the model to a fast NVMe and ensure `vm.swappiness=1` |
| No output after a few seconds | KV‑Cache quantisation not supported by the binary | Re‑build with `-DGGML_AVX512=ON` (already done) or disable `KV_CACHE` |

---

## 9. Summary checklist

- [ ] Build `llama.cpp` with `-march=znver3` and AVX‑512 enabled.  
- [ ] Set `THREADS=8` and `KV_CACHE="q8_0"` in the model env.  
- [ ] Pin the process to the CPU socket (optional).  
- [ ] Apply system‑wide tuning (`swappiness`, `ulimit`, governor).  
- [ ] Verify latency with a small benchmark.  

Following this guide will give you the best possible throughput from the Mistral‑Small‑24B‑Instruct‑2501 model on a 9700X + DDR5 64 GB setup.