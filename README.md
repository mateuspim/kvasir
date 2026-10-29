# local-llm-stack

A local, OpenAI-compatible LLM endpoint for coding agents — one
[Strata](https://github.com/Niko1221/Strata) container serving
**Qwen3.8 Flash-Next** (125B MoE, ~6B active) on a 16 GB card, wired into
[opencode](https://opencode.ai).

Model choice follows Akita's
[llm-opensource-benchmark](https://github.com/akitaonrails/llm-opensource-benchmark):
Q2_0 matched IQ3_S on his hard coding canary (36/36 hidden tests, 3 of 3 runs)
and is the fastest quant everywhere he measured it.

## Measured on this hardware

RTX 4080 (16 GB) · Ryzen 9 9900X · 60 GB RAM · Strata image 0.2.7-cuda13 (engine 0.1.52)

| Prompt | TTFT | Prefill | Decode |
|--------|------|---------|--------|
| ~5.3K tokens | 1.6 s | ~3,400 tok/s | **126–131 tok/s** |
| ~41K tokens | 11.3 s | ~3,600 tok/s | **113–122 tok/s** |

Q2_0, 128K context, int8 KV, MTP speculative decoding. 15.6/16.4 GB VRAM,
~36 GB RAM. Decode is an upper bound: the benchmark filler is repetitive code,
which MTP drafts unusually well.

**Coding quality:** 100/100 on Akita's hard canary (36/36 hidden tests, 4 turns,
up to ~113K tokens of context) in 14.8 min — the same score as his 5090, at
about half the speed.

For comparison, the previous llama-swap stack ran Qwen3.6-35B-A3B at 87–93
tok/s on the same card.

## Quick start

```bash
cp .env.example .env      # paths must be absolute (pkexec)
make key                  # API key -> ~/.config/local-llm/strata.key, mode 600
make plan                 # dry run: what would download, changes nothing
make up                   # first start downloads ~72 GB, builds a ~38 GB pack
make status
```

```bash
make test                 # config tests (fast, offline, no GPU)
make bench                # speed canary (needs an idle GPU)
```

## Four things worth knowing

**Docker runs through `pkexec`, never the docker group.** Membership in
`docker` is root-equivalent. Every target that touches docker prompts via
polkit instead. pkexec drops the environment, which is why `.env` must hold
absolute paths — there is a test for it.

**Keep the data on NVMe.** Strata leaves a 29 GB lookup shard on disk and reads
rows from it *during generation*, not only at load. A SATA SSD costs decode
speed, not just startup time.

**RAM is the tight resource, not VRAM.** Q2_0 keeps ~34 GB of experts in RAM,
leaving ~9 GB free on a 60 GB box. A big browser session or a game alongside it
can trigger the OOM killer. IQ3_XXS (43 GB of experts) still fits, with less
margin.

**opencode 2.2's background service defaults to port 49374** — the same port
the ai-memory server uses. `opencode run` then dies with "Managed service port
49374 … already in use". Fixed with `opencode service set port 49380`.

## Layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | the `strata` service: pinned image, loopback port, key as a secret |
| `.env.example` | data dir, key file, model selection |
| `scripts/speed.py` | Akita-style speed canary (cold prompts, 256 tokens out) |
| `scripts/test_config.sh` | config tests, also run as a pre-commit hook |
| `CLAUDE.md` | full notes, including the opencode-side config |

Weights never touch the repo: they live in `$STRATA_DATA_DIR`. `.gitignore`
excludes `*.gguf` and pre-commit caps file size as a backstop.
