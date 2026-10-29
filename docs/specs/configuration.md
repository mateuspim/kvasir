# Configuration

Everything is configured in `.env`, created from `.env.example` by `make env`.
The Makefile includes it, and compose reads it with an absolute `--env-file`
path. Because the default `DOCKER=pkexec docker` resets the environment,
variables exported in your shell are **not** seen by compose: put them in
`.env`.

## Variables

| Variable | Default | Required | Meaning |
| --- | --- | --- | --- |
| `STRATA_DATA_DIR` | `/srv/strata-data` | yes | Absolute host path mounted at `/data`. Holds GGUFs, the prepared pack, the MTP draft, presets and logs (~105 GB for Q2_0). Must exist before `make up`. Put it on NVMe ([ADR 5](../adr/0005-keep-model-data-on-nvme.md)). |
| `STRATA_KEY_FILE` | `$HOME/.config/kvasir/strata.key` (written by `make env`) | yes | Absolute path of the API key file, one line, mode 0600. Mounted as the compose secret `strata_key`. |
| `STRATA_PORT` | `8080` | no | Host port, always bound to `127.0.0.1`. |
| `GPU_VENDOR` | `nvidia` | no | Picks `compose/<vendor>.yml`: `nvidia` or `amd`. |
| `STRATA_IMAGE` | `ghcr.io/niko1221/strata:0.2.7-cuda13` | no | Pinned image ([ADR 6](../adr/0006-pin-the-image-tag.md)). Pick the flavor for your card in the [hardware guide](../guide/hardware.md). |
| `RENDER_GID` | the host's `render` group id (written by `make env`) | AMD only | Numeric group id passed to the container for `/dev/dri`. |
| `DOCKER` | `pkexec docker` | no | How docker is invoked ([ADR 3](../adr/0003-reach-docker-through-pkexec.md)). |
| `FAMILY` | `qwen` | no | Strata model family: `qwen`, `coder`, `swift`, … |
| `MODEL` | `Q2_0` | no | Size within the family: `Q2_0`, `IQ2_XS`, `IQ3_XXS`, `IQ3_S`, … Also forms the model id. |
| `CONTEXT` | `128k` | no | `32k`, `64k`, `128k`, `256k` or a token count. |
| `KV` | `int8` | no | KV cache format: `int8`, `q4_0`, `k8v4`, `fp16`. |
| `VISION` | `on` | no | `on`, `off`, `gpu` or `cpu`. `on` downloads a 0.9 GB picture reader. |
| `TUNE` | `skip` | no | `quick` (up to ~20 min) or `thorough` (up to ~2 h) tunes once and saves it in the preset. |

The model variables map one to one onto the image's entrypoint settings; see
Strata's [Docker documentation](https://github.com/Niko1221/Strata/blob/main/docs/DOCKER.md)
for the full list. The entrypoint saves them into a preset named `docker`;
changing them and running `make restart` overwrites that preset.

## Make targets

| Target | Docker? | Does |
| --- | --- | --- |
| `env` | no | Writes `.env` from `.env.example` with this machine's key path and render group. Never overwrites. |
| `key` | no | Creates the key file, mode 0600, in a 0700 directory. Never overwrites. |
| `plan` | yes | Runs `strata launch --plan` in a throwaway container with the same GPU and volume as `up`. Prints the download size; changes nothing. |
| `up` | yes | Checks `.env`, the key file and the data directory, then `compose up -d`. |
| `down` | yes | Stops the stack; the model drains and unloads. |
| `restart` | yes | Recreates the container, picking up `.env` changes. |
| `logs` | yes | Follows the container log. |
| `pull` | yes | Pulls `STRATA_IMAGE`. |
| `shell` | yes | Opens `/bin/sh` in the running container. |
| `status` | no | GPU memory, system RAM, and the model id the endpoint serves. |
| `bench` | no | Runs `scripts/speed.py` against the endpoint. |
| `curl-test` | no | Sends one tool-calling request and prints the response. |
| `du` | no | Disk used under `STRATA_DATA_DIR/Strata-data`. |
| `test` | no | `scripts/test_config.sh`; offline, no GPU, no daemon. |
| `lint` | no | Every pre-commit hook over all files. |
