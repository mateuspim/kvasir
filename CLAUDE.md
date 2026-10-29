# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

A local, OpenAI-compatible LLM endpoint for coding agents (opencode, Claude Code,
anything that speaks the OpenAI API). A single
[Strata](https://github.com/Niko1221/Strata) container serves Qwen3.8 Flash-Next
Q2_0 from the official image `ghcr.io/niko1221/strata:<version>-cuda13`.

Endpoint: `http://127.0.0.1:8080/v1`, model id `qwen3.8-flash-next-q2_0`.
Every request needs `Authorization: Bearer <key>`; the key is in
`$STRATA_KEY_FILE` (default `~/.config/local-llm/strata.key`).

This replaced a llama-swap + llama.cpp stack (Qwen3.6-35B-A3B and gpt-oss-20b)
on 2026-10-29. That setup is in git history if it is ever needed again.

## Tests

```bash
make test    # config tests: fast, offline, no GPU, no docker daemon
make lint    # every pre-commit hook over all files
```

`scripts/test_config.sh` checks the failure modes this setup can actually hit:

| Test | Regression it catches |
|------|----------------------|
| loopback-only publish | offering the endpoint to the LAN |
| `/data` is a bind mount | a named volume putting ~105 GB on the root disk |
| image pinned in compose *and* `.env.example` | a `latest-*` tag silently swapping the engine under a saved preset |
| key comes from `/run/secrets` | the key pasted into compose or `.env`, visible in `docker inspect` |
| `.env` paths absolute | `~` or `$HOME` in `.env`, which pkexec does not expand |
| key file mode 600 | a world-readable key |

Each of these was verified to fail the suite when its regression was
introduced. A test that cannot fail is worth nothing — if you add one, prove
it catches its bug before trusting it.

## Common Commands

```bash
make help        # list all targets
make key         # create the API key file (never overwrites)
make plan        # dry run of a MODEL/CONTEXT change: download size, nothing changed
make up          # start (first run downloads the model)
make status      # GPU + RAM + the model the endpoint serves
make bench       # speed canary
make curl-test   # verify tool calling works end to end
make logs
```

## Key Conventions

- **Docker only through `pkexec`.** The user is deliberately not in the
  `docker` group and must not be added to it. The Makefile sets
  `DOCKER ?= pkexec docker` and passes compose absolute `--project-directory`,
  `--env-file` and `-f` paths, because pkexec resets the environment.
- **The image tag is pinned.** Upgrading means changing `STRATA_IMAGE` in
  `.env` (and the default in compose), then `make restart`. The entrypoint
  drops run settings that name an engine folder the new image lacks, and
  rebuilds them from the kept model files — no re-download.
- **Model data lives in `$STRATA_DATA_DIR`** (`/mnt/sleipnir/llm-models/strata-data`,
  Gen4 NVMe). Layout inside: `Strata-data/models/Q2_0` (63 GB of GGUF),
  `Strata-data/packs/q2_0` (38 GB, built by Strata on first start),
  `Strata-data/mtp` (draft layer). Not `/mnt/gungnir`: that is a SATA SSD and
  Strata reads the 29 GB lookup shard during generation.
- **The entrypoint saves settings into a preset named `docker`.** Changing
  `MODEL`/`CONTEXT`/`KV`/`VISION` in `.env` and running `make restart`
  overwrites it; with no settings given, the saved preset is reused.

## Hardware Context

| | |
|---|---|
| GPU | RTX 4080, 16 GB VRAM (sm_89), driver 615 |
| CPU | Ryzen 9 9900X, 12c/24t, AVX-512 |
| RAM | 60 GB — **the binding constraint for this model** |
| Model disk | `/mnt/sleipnir`, Kingston Fury Renegade Gen4 NVMe |

Basalt, the faster Strata fork Akita used on his 5090, is Blackwell-only
(sm_120) and does not apply to this card.

## Measured Results

Measured 2026-10-29, `make bench`, GPU otherwise idle.

| Prompt | TTFT | Prefill | Decode |
|--------|------|---------|--------|
| ~5.3K tokens | 1.6 s | ~3,400 tok/s | 126–131 tok/s |
| ~41K tokens | 11.3 s | ~3,600 tok/s | 113–122 tok/s |

Memory with the model loaded: 15.6/16.4 GB VRAM (Strata fills the card with an
expert cache on purpose), 51/60 GB RAM used system-wide.

Reference points: Akita's 5090 on Strata 245–270 tok/s; a community RTX 5060
Ti 16 GB run (abliterated Q2_0) 68–73 tok/s; this card on the old llama.cpp
stack with Qwen3.6-35B-A3B, 87–93 tok/s.

**Decode figures are an upper bound.** The filler is repetitive code that MTP
drafts unusually well.

### Coding quality: Akita's hard canary

`bench/hard_canary.py` from his repo, 2026-10-29, one run: **100/100, 36/36
hidden tests**, 14.8 min for the 4 turns (his 5090: 7.1 min on Strata, 5.5 on
Basalt, same score). 137 requests, largest prompt ~113K tokens.

To rerun it against this endpoint, the gateway in his `bench/sandbox.py` must
send the real key: replace the hard-coded `"Bearer local"` with
`"Bearer " + os.environ.get("BENCH_API_KEY", "local")`, then:

```bash
BENCH_API_KEY=$(cat ~/.config/local-llm/strata.key) python3 bench/hard_canary.py \
  --base-url http://127.0.0.1:8080/v1 --model qwen3.8-flash-next-q2_0 \
  --provider strata-4080-docker --label <label> --output results/hard/<label>
```

The key stays on the host side of the gateway; the sandbox never sees it.

**Measure with the GPU to itself.** Anything else holding VRAM pushes experts
off the card and reads 3–8x too low while still looking plausible.

## opencode integration

Config lives in `~/.config/opencode/opencode.json` (not in this repo): an
`@ai-sdk/openai-compatible` provider named `strata` at
`http://127.0.0.1:8080/v1`, with `"apiKey": "{file:~/.config/local-llm/strata.key}"`
so the key is never written into the config. Non-obvious pieces:

- **`attachment: true` and `modalities.input: ["text","image"]`** are needed for
  vision, separately from `VISION=on` on the server. Without them opencode never
  sends the image and the model claims it cannot see images.
- **`limit.context` must match `CONTEXT`** (131072). opencode decides when to
  compact from that number.
- **opencode 2.2's background service defaults to port 49374**, which the
  ai-memory server already holds. Moved with `opencode service set port 49380`.
- **LSP: `pyright` is disabled, `basedpyright` replaces it.** opencode's bundled
  pyright is too old to parse under Node 26 and dies with
  `SyntaxError: Invalid or unexpected token` in `vendor.js` before it can start.
  basedpyright (installed with `uv tool install basedpyright`) ships its own
  Node 24 via `nodejs-wheel-binaries` and is immune to the host Node version.
- **Akita's benchmark sandbox binds opencode 2.1.4's native binary** from the
  mise install path. 2.1.4 is installed with mise alongside the global `latest`.
