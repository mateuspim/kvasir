# Kvasir agent instructions

Kvasir runs a local, OpenAI-compatible LLM endpoint for coding agents:
one [Strata](https://github.com/Niko1221/Strata) container, driven by Docker
Compose and a Makefile, serving Qwen3.8 Flash-Next on a consumer GPU. Public at
https://github.com/mateuspim/kvasir. The README is the user manual;
`docs/architecture.md` says how the parts fit, `docs/adr/` why, `docs/specs/`
what the contracts are, `docs/guide/` how to use each piece.

## Project

- Layout: `docker-compose.yml` is the service; `compose/<vendor>.yml` adds GPU
  access and is chosen by `GPU_VENDOR`; `Makefile` is the only entry point
  people should need; `scripts/` holds the config tests and the speed canary.
  There is no application code: behaviour lives in the upstream image.
- Naming: compose project `kvasir`; container and compose service `strata`; variables are the ones in
  `.env.example` and [docs/specs/configuration.md](docs/specs/configuration.md);
  model ids are `qwen3.8-flash-next-<model lowercased>`.
- Docker only through `$(DOCKER)`, which the Makefile detects: plain `docker`
  when it already works, else `pkexec docker`, else `sudo docker` (ADR 8).
  Never tell anyone to join the `docker` group to make the stack work; it is
  root-equivalent. pkexec and sudo reset the environment, so every path
  compose sees must be absolute and come from `.env`.
- The endpoint stays on `127.0.0.1` and always requires the key, which reaches
  the container only as a compose secret (ADR 4).
- Model data is a bind mount on NVMe, never a named volume (ADR 5).
- The image tag is pinned in both the compose default and `.env.example`
  (ADR 6). Upgrading is a deliberate edit, never a `latest-*` tag.
- Never `docker rm`, restart or `make down` the owner's running container
  without asking: it holds ~16 GB of VRAM and ~34 GB of RAM and takes minutes
  to come back on a cold page cache.

## Code style

- Match the surrounding file: Makefile recipes with tabs, `printf` over `echo -e`,
  bash with `set -uo pipefail` in scripts.
- Compose and `.env.example` comments explain why a value is what it is; keep
  them next to the value they explain.
- Error messages name the offending value and the fix (`no key file: make key`).

## Comments

- Keep existing comments; they carry intent and provenance.
- Write WHY, not WHAT. Name the upstream behaviour or measurement a line exists
  for, and link the ADR when there is one.

## Tests

- `make test` runs everything; CI runs the same script. It is offline: it
  renders compose client-side and never needs a GPU or the docker daemon.
- Every check guards a failure mode this setup can actually hit. A check that
  cannot fail is worth nothing: when adding one, break the thing it guards and
  show it fails before trusting it.
- Anything needing the GPU (`make bench`, the hard canary) is a manual step,
  never a hook, and needs the GPU to itself: other VRAM users make results
  read 3-8x too low while still looking plausible.
- Never run downloaded benchmark code without reading it first and without the
  owner's go-ahead.

## Dependencies

- Runtime: Docker with Compose v2, the GPU's container runtime, `make`, `curl`,
  `openssl`, `python3` (stdlib only). Do not add Python packages or a venv.
- The engine comes only from the pinned official image. Do not add host
  installs of Strata (install.sh, mise, AUR) to the Makefile (ADR 7).

## Public-repo hygiene

- No `/home/<user>` paths (the placeholder is `/home/you`), real mount names,
  hostnames, LAN addresses or keys in tracked files. `make test` checks home
  paths.
- `.env` and the key file are never committed.
- `HANDOFF.md` is local-only and stays gitignored.

## Commits and releases

- Branch `master`. Commit subjects are plain imperative sentences with a body
  that says why. Ask the owner before pushing commits or tags, and before
  publishing a GitHub release.
- Release: add the `CHANGELOG.md` entry, check the README and guides cover the
  change, run `make test`, commit `Release X.Y.Z`, annotated tag `vX.Y.Z`.
