# Troubleshooting

Each entry: what you see, why, and the fix.

## `permission denied while trying to connect to the docker API`

**Cause:** docker was called directly as your user, outside the Makefile.
**Fix:** use the make targets, which run docker as `$(DOCKER)` (default
`pkexec docker`). Do not add yourself to the `docker` group to make this go
away ([ADR 3](../adr/0003-reach-docker-through-pkexec.md)). Without polkit,
set `DOCKER=sudo docker` in `.env`.

## `set STRATA_DATA_DIR in .env` / `STRATA_DATA_DIR does not exist`

**Cause:** `.env` is missing the data path, or it points at a directory that
has not been created.
**Fix:** set an absolute path on an NVMe drive in `.env` and create the
directory.

## Compose cannot find the key file, or `~/…` paths fail

**Cause:** pkexec resets the environment, so `~` and `$HOME` in `.env` are
not expanded.
**Fix:** absolute paths only. `make env` writes them; `make test` flags
relative ones.

## `The engine in this image does not match this computer's graphics card`

**Cause:** the wrong `STRATA_IMAGE` flavor or `GPU_VENDOR`, or the container
cannot see the GPU.
**Fix:** pick the row for your card in the
[hardware guide](../guide/hardware.md). NVIDIA needs nvidia-container-toolkit
and driver 580+ for `cuda13`. AMD needs `RENDER_GID` set (`make env`).

## First start takes a long time, endpoint refuses connections

**Cause:** the first start downloads ~72 GB and builds a ~38 GB pack before it
opens the port. The healthcheck reports `starting`, not `unhealthy`, for up to
two hours.
**Fix:** wait, and watch with `make logs` or `make du`. An interrupted
download resumes on the next start.

## 401 Unauthorized

**Cause:** the client sends no key or a different one.
**Fix:** send the contents of `STRATA_KEY_FILE` as a bearer token. In
opencode, use `"apiKey": "{file:…}"` pointing at the same file
([opencode guide](../guide/opencode.md)).

## Speed is a fraction of the published numbers

**Cause:** something else is holding VRAM, so Strata keeps fewer experts on
the card. The result looks plausible but can be 3-8x too low.
**Fix:** check `make status` with the model loaded and nothing else running.
Close other model servers, games and GPU-heavy browser tabs, then measure
again.

## The container is killed, or the desktop freezes under load

**Cause:** RAM. Q2_0 keeps ~34 GB of experts in RAM; with a large browser
session or a game on top, the kernel's or systemd's out-of-memory killer
steps in.
**Fix:** close memory-heavy apps while serving, choose a smaller `MODEL`, or
add RAM. `free -g` in `make status` shows the headroom.

## opencode: `Managed service port 49374 … already in use`

**Cause:** opencode 2.2's background service defaults to port 49374, which
other local tools may already use.
**Fix:** `opencode service set port <free port>`, for example 49380.

## opencode: "I can't view images"

**Cause:** the opencode model entry lacks `attachment: true` or the image
input modality, so the image is never sent.
**Fix:** add both ([opencode guide](../guide/opencode.md)), and keep
`VISION` at `on` on the server.
