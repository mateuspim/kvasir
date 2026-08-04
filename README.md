# local-llm-stack

A local, OpenAI-compatible LLM endpoint for coding agents — one `llama-swap`
container fronting several GGUF models, hot-swapped on demand, wired into
[opencode](https://opencode.ai).

Built and tuned for a **16 GB card**, which is the constraint that drives almost
every decision here.

## Measured on this hardware

RTX 4080 (16 GB) · Ryzen 9 9900X · 60 GB RAM · llama.cpp b10236

| Model | Context | VRAM | Generation |
|-------|---------|------|-----------|
| Qwen3.6-35B-A3B Q4_K_XL + MTP | 131072 | 14.2 GB | **87–93 tok/s** |
| gpt-oss-20b MXFP4 + eagle3 | 65536 | ~13.5 GB | **221 tok/s** |

Both do tool calling; the Qwen also does vision.

## Quick start

```bash
cp .env.example .env      # set MODELS_DIR
make models               # ~36 GB of weights
make up                   # endpoint on 127.0.0.1:8080/v1
make status
```

```bash
make test                 # config tests (fast, offline, no GPU)
make tune                 # measure the best draft depth (needs an idle GPU)
```

## Four things that cost real time to work out

**Do not set `--n-gpu-layers` or `--n-cpu-moe`.** Setting either makes llama.cpp
abandon its own memory fitting — it logs `n_gpu_layers already set by user,
abort` — and fall back to your hard-coded value, which OOMs at 128K context.
Left alone, `common_fit_params` computes the split at load time and lands at
14.2/16.4 GB with the full window. There is a test guarding this.

**Pick the MoE, not the dense model.** Qwen3.6-27B scores higher on paper (77.2
vs 73.4 SWE-bench Verified) but reads all 27B params per token, so it cannot
spill to RAM cheaply. The 35B-A3B activates ~3B per token and wins decisively on
a 16 GB card. Published tok/s figures for these models are usually RTX 5090
numbers — assume roughly a third of them here.

**Long context is cheap on this architecture.** Only 10 of 40 layers keep a KV
cache; the other 30 are Gated DeltaNet with fixed-size state. The full 128K
window costs ~1.4 GB, roughly a quarter of what a conventional transformer of
this size would need. Shrinking the context to free VRAM is not worth it.

**Speculative decoding peaks early.** Deeper drafts get rejected faster than
they pay for themselves — `eagle3` at depth 5 is *slower than no speculation at
all*. Measured optima: MTP depth 2 for the Qwen, eagle3 depth 3 for gpt-oss.

## Benchmarking

Measurements taken while anything else holds VRAM come out **3–8× too low** and
still look plausible. `scripts/tune.sh` refuses to run above 500 MiB of GPU use,
and averages several samples per setting because single runs vary by ~10% —
enough to pick the wrong value outright.

## Layout

| Path | Purpose |
|------|---------|
| `config/llama-swap.yaml` | model definitions, per-model llama-server flags |
| `models.conf` | INI download manifest, `filename = url` |
| `scripts/fetch_models.sh` | resumable, size-verified downloads |
| `scripts/tune.sh` | draft-depth sweep with a GPU-idle guard |
| `scripts/test_config.sh` | config tests, also run as a pre-commit hook |
| `CLAUDE.md` | full notes, including the opencode-side gotchas |

Weights are never committed — they live in `$MODELS_DIR`, bind-mounted
read-only. `.gitignore` excludes `*.gguf` and pre-commit caps file size as a
backstop.
