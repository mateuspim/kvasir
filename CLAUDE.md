# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

A local, OpenAI-compatible LLM endpoint for coding agents (opencode, Claude Code,
Hermes, anything that speaks the OpenAI API). A single `llama-swap` container
fronts several GGUF models and hot-swaps between them on demand, so a primary
agent and its subagents can each use a different model through one URL.

Endpoint: `http://localhost:8080/v1`

## Tests

```bash
make test    # config tests: fast, offline, no GPU
make lint    # every pre-commit hook over all files
```

Hooks are installed (`pre-commit install`) and run on every commit. They are
deliberately all fast and offline — `make tune` is **not** a hook, because it
needs minutes and an idle GPU.

`scripts/test_config.sh` checks the failure modes this project actually hit,
not hypothetical ones:

| Test | Regression it catches |
|------|----------------------|
| referenced files exist on disk | a model advertised with no weights — llama-swap starts fine, then 500s on every request to it |
| no `--n-gpu-layers` / `--n-cpu-moe` | re-adding either makes llama.cpp abandon its own memory fitting and OOM at 128K |
| loopback-only publish | exposing an unauthenticated inference endpoint to the LAN |
| YAML/compose validity, `bash -n`, https URLs | ordinary breakage |

All four regression paths were verified to actually fail the suite, and a real
bad commit was confirmed blocked. A test that cannot fail is worth nothing —
if you add one, prove it catches its bug before trusting it.

## Common Commands

```bash
make help        # list all targets
make models      # download every enabled model in models.conf (idempotent, resumable)
make up          # start
make status      # container state + GPU memory + models llama-swap knows about
make tune        # measure the best --n-cpu-moe for this box
make curl-test   # verify tool calling works end to end
make logs
```

## Hardware Context

This config is tuned for one specific machine, and most of the non-obvious
choices follow from it:

| | |
|---|---|
| GPU | RTX 4080, **16 GB VRAM** — the binding constraint |
| CPU | Ryzen 9 9900X, 12c/24t, full-width AVX-512 (`avx512_bf16`, `avx512_vnni`) |
| RAM | 60 GB usable |
| Models on | `/mnt/FastGames` (Gen4 NVMe ~7000 MB/s), **not** `/mnt/Tools` (SATA ~530 MB/s) |

`ggml` picks its `zen4` CPU backend at runtime, so expert tensors offloaded to
system RAM still run the AVX-512 path.

## Architecture

### Why MoE and not dense

The primary model is Qwen3.6-**35B-A3B** (MoE) rather than Qwen3.6-**27B**
(dense), even though the dense model scores higher (77.2 vs 73.4 SWE-bench
Verified). On a 16 GB card that ranking inverts:

- Dense 27B reads all 27B params per token. It cannot fit in 16 GB at Q4, and
  offloading a dense model to RAM is punishing.
- MoE 35B-A3B activates only ~3B params per token, so pushing its expert
  tensors into RAM via `--n-cpu-moe` costs comparatively little.

Anything written about these models assuming a 24 GB or 32 GB card does not
transfer directly — most published Qwen3.6 tok/s figures are RTX 5090 numbers.

### Speculative decoding

Both serving tiers use it, via different mechanisms:

- **qwen3.6-35b** — `--spec-type draft-mtp`. Weights come from the `-MTP-`
  Unsloth repo, which bundles a multi-token-prediction head (~845M extra
  params). Worth 1.4–2.2x generation speed.
- **gpt-oss-20b** — `--spec-type draft-eagle3` with `ggml-org`'s matched
  eagle3 draft model, since gpt-oss has no MTP head.

### Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Single `llama-swap` service, GPU-enabled |
| `config/llama-swap.yaml` | Model definitions, per-model llama-server flags, `macros` for shared flags |
| `models.conf` | INI download manifest, `filename = url`. Comment a line out to skip |
| `scripts/fetch_models.sh` | Reads `models.conf`, resumable downloads, size-verified |
| `scripts/tune.sh` | Sweeps `--n-cpu-moe`, reports the optimum |

## opencode integration

Config lives in `~/.config/opencode/opencode.json` (not in this repo). Points at
`http://localhost:8080/v1` via an `@ai-sdk/openai-compatible` provider named
`llamaswap`. Non-obvious pieces:

- **`attachment: true` is required for vision**, separately from the server-side
  `--mmproj`. Without it opencode never sends the image at all, and the model
  replies "I can't view images" — which reads like a model limitation but is a
  client-side config gap.
- **`limit.context` must match `--ctx-size`** here. opencode decides when to
  compact from that number; undeclared, it guesses wrong in both directions.
- **`small_model` points at the *same* model as the primary, deliberately.**
  Pointing it at the other local model would make every session-title generation
  evict a 22 GB model and load a 12 GB one, then swap back. With one GPU, a
  second local model is never the cheap option.
- **LSP: `pyright` is disabled, `basedpyright` replaces it.** opencode's bundled
  pyright is too old to parse under Node 26 and dies with
  `SyntaxError: Invalid or unexpected token` in `vendor.js` before it can start.
  basedpyright (installed with `uv tool install basedpyright`) ships its own
  Node 24 via `nodejs-wheel-binaries` and is immune to the host Node version.
  Note `lsp` as an *object* keeps all other default servers enabled; only
  omitting the key entirely disables everything.

## Key Conventions

- **Model weights never live in this repo.** They go in `$MODELS_DIR`
  (`/mnt/FastGames/llm-models`), bind-mounted read-only at `/models`.
- **The `-MTP-` repos contain files with no `MTP` in their names.**
  `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` ships `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf`.
  Do not "correct" the filenames in `models.conf` to match the repo name.
- **`--n-cpu-moe` and `--spec-draft-n-max` are measured, not chosen.** Values in
  `config/llama-swap.yaml` are starting points until `make tune` has run. Record
  measured values here when they are known.
- **This image has no `llama-bench`.** It ships the unified `llama` CLI —
  use `llama bench`, `llama fit-params`, `llama serve`.
- **Sampler settings are Unsloth's documented coding preset** (temp 0.6,
  top-p 0.95, top-k 20, min-p 0.0, repeat penalty off). Their general-purpose
  preset uses temp 1.0; do not mix them up.
- **CUDA 13.2 produces gibberish** with these models. This host is on 13.3.

## Measured Results

Measured 2026-08-03 on the hardware above, 400-token code-generation prompt.

| Model | ctx | VRAM | spec setting | gen tok/s | draft accept |
|-------|-----|------|--------------|-----------|--------------|
| Qwen3.6-35B-A3B Q4_K_XL | 131072 | 14256 MiB | `draft-mtp`, n-max **2** | **87–93** | 71.6% |
| gpt-oss-20b MXFP4 | 65536 | ~13.5 GB | `draft-eagle3`, n-max **3** | **221** | 53.5% |

Sweeps behind those choices:

```
35B  MTP n-max:   1 -> 86.8   2 -> 87.4   3 -> 78.5   4 -> 76.9   6 -> 66.0
20B  eagle3:   none -> 194.0  1 -> 209.9  2 -> 219.4  3 -> 221.5  5 -> 191.7
```

Both curves peak early and then decline: deeper drafts get rejected more often
than they save. eagle3 at n-max 5 is *slower than no speculation at all*.

**Single samples are not trustworthy.** Repeat runs of the same setting vary by
~10%. A one-shot sweep once reported n-max=3 as best (98.9 tok/s); three repeats
of each showed n-max=2 ahead, 94.2 vs 89.2. `tune.sh` now averages `REPS`
(default 3) samples per setting for this reason.

### --reasoning-preserve: measured, rejected

llama.cpp suggests it at load time ("chat template supports preserving
reasoning") and Unsloth documents it as maintaining the reasoning trace across
turns. Measured on a two-turn dependent-arithmetic task:

| | turn-2 prompt tokens | answer |
|---|---|---|
| `--no-reasoning-preserve` | 116 | correct |
| `--reasoning-preserve` | 480 | correct |

**4.1x the context for an identical answer.** Not enabled. Revisit only if a
long agentic chain shows a quality difference that this test could not.

### Benchmarking methodology -- read before re-measuring

**Every benchmark container must have the GPU to itself.** Measurements taken
while another model held VRAM came out 3-8x too low (35B read 17-20 tok/s
instead of 87; 20B read 25-30 instead of 221) because the contending process
forced tensors onto the CPU. The numbers looked plausible, which is what makes
this dangerous.

Before any sweep:

```bash
make down                     # llama-swap keeps models resident on a TTL
docker ps | grep llama        # nothing else may be running
nvidia-smi --query-gpu=memory.used --format=csv,noheader   # must be < 500 MiB
```

`scripts/tune.sh` should assert this before each run rather than trusting it.
