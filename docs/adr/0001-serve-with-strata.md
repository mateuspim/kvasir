# 1. Serve with Strata instead of llama.cpp behind llama-swap

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

The first version of this repo ran llama-swap in front of llama.cpp, serving
Qwen3.6-35B-A3B (87-93 tok/s) and gpt-oss-20b on a 16 GB card and swapping
between them on demand.

Akita's [llm-opensource-benchmark](https://github.com/akitaonrails/llm-opensource-benchmark)
showed Qwen3.8 Flash-Next, a 125B mixture-of-experts model with about 6B
active parameters, passing a hard multi-turn opencode canary at 2-bit. A model
that size does not fit a 16 GB card. Strata serves it by keeping a cache of
the most-used experts in VRAM, the rest of the experts in RAM, and a lookup
shard on the SSD.

## Decision

Serve Qwen3.8 Flash-Next with Strata. Remove the llama-swap config, the model
manifest, and the download and tuning scripts.

## Consequences

- Measured on an RTX 4080 with 60 GB of RAM: 113-131 tok/s decode, and
  100/100 on Akita's hard canary.
- One model at a time. Changing model means changing `.env` and restarting,
  which can mean downloading tens of GB.
- RAM becomes the binding resource, not VRAM: about 9 GB stays free on a 60 GB
  machine with Q2_0 loaded.
- Strata's flags and file layout differ from llama.cpp's; nothing from the old
  tuning carries over. The old setup remains in git history before this
  change.
