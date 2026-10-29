# Architecture

Kvasir has no application code of its own. It is the configuration
that runs one upstream container safely and repeatably: a compose file, a GPU
override, a Makefile, and two scripts. The model server is
[Strata](https://github.com/Niko1221/Strata), from its official image.

## Components

| Part | Role |
| --- | --- |
| `Makefile` | The entry point. Reads `.env`, invokes docker as `$(DOCKER)` (plain `docker`, `pkexec docker` or `sudo docker`, detected), and refuses to start when `.env`, the key file or the data directory is missing. |
| `docker-compose.yml` | The `strata` service: pinned image, loopback-only port, model settings as environment variables, the key as a secret, `/data` as a bind mount. |
| `compose/nvidia.yml`, `compose/amd.yml` | GPU access for each vendor, chosen by `GPU_VENDOR`. |
| `ghcr.io/niko1221/strata` image | Strata's Terminal plus one GPU engine package. Its entrypoint turns the environment into `strata launch --no-tui`. |
| `scripts/test_config.sh` | Offline checks on the rendered compose config and `.env`; `make test` and CI. |
| `scripts/speed.py` | Speed canary against the running endpoint; `make bench`. |

## Request path

```text
opencode / any OpenAI client
   │  POST /v1/chat/completions   Authorization: Bearer <key>
   ▼
127.0.0.1:8080  (published by docker; nothing listens on other addresses)
   ▼
container "strata": tini → entrypoint.sh → strata launch → engine
   │                                         │
   │  key from /run/secrets/strata_key       │  model data from /data
   ▼                                         ▼
 rejects requests without the key        STRATA_DATA_DIR (bind mount, NVMe)
```

## Where the model lives while serving

Qwen3.8 Flash-Next is a mixture-of-experts model: 125B parameters, about 6B
active per token. Strata splits it across three tiers, which is why the
hardware guide talks about RAM before VRAM:

| Tier | Holds | Q2_0 size |
| --- | --- | --- |
| VRAM | Dense layers, KV cache, MTP draft head, and a cache of the most-used experts that fills what is left | ~15.6 GB of a 16 GB card |
| RAM | Every expert from the first model shard | ~34 GB |
| NVMe (`/data`) | The second shard, a lookup table read row by row during generation | 29 GB |

## Lifecycle

1. **First `make up`**: the entrypoint downloads the model (~66 GB), the MTP
   draft (~5 GB) and, with `VISION=on`, the picture reader (~0.9 GB) into
   `/data/Strata-data`, then builds Strata's own pack (~38 GB) from the GGUF
   files. It saves the settings as a preset named `docker`. This takes tens of
   minutes and depends on your connection.
2. **Later starts**: files and the pack are reused, so the model loads in about
   25 seconds on NVMe with a warm page cache.
3. **`make down`** sends SIGTERM; the entrypoint runs `strata launch --stop`,
   which drains requests and frees the GPU. Compose allows two minutes.

## Boundaries

- Nothing outside the repo directory, the key file and `STRATA_DATA_DIR` is
  written. No packages, services or groups are changed on the host.
- The engine version is whatever the pinned image carries. This repo does not
  build or patch Strata.
- One model at a time. Strata has no hot-swapping between models the way the
  earlier llama-swap setup did ([ADR 1](adr/0001-serve-with-strata.md)).
