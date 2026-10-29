# Changelog

## Unreleased

- Rename the project to Kvasir. The repository moves to
  `github.com/mateuspim/kvasir` (GitHub redirects the old URL), the default
  key path for new installs becomes `~/.config/kvasir/strata.key`, and the
  compose project is pinned to the name `kvasir`.
  **Existing installs:** an `.env` that sets `STRATA_KEY_FILE` keeps working.
  The running container belongs to the old compose project, so remove it
  once with `docker rm -f strata` (through sudo or pkexec if you need them),
  then `make up`; model data is kept.
- Detect how to reach docker: plain `docker` when it already works, else
  `pkexec`, else `sudo`. pkexec is no longer forced on everyone.
- Serve Qwen3.8 Flash-Next Q2_0 with the official Strata image instead of
  llama-swap and llama.cpp. Measured on an RTX 4080 with 60 GB of RAM:
  113-131 tok/s decode, and 100/100 (36/36 hidden tests) on Akita's hard
  opencode canary.
- Pass the API key as a compose secret from a 0600 file.
- Support NVIDIA and AMD through `compose/<vendor>.yml`, chosen by
  `GPU_VENDOR`. AMD is untested.
- Add `make env`, `key`, `plan`, `bench` and `curl-test`.
- Rewrite the config tests for this setup: loopback publish, bind-mounted
  data, pinned image, key handling, `.env` paths, home-path leaks.
- Add the docs tree, ADRs, specs, guides, CI and branding.
- Remove the llama-swap config, model manifest, download and tuning scripts.

## 0.1.0 - 2026-08-04

- First version: llama-swap fronting Qwen3.6-35B-A3B (87-93 tok/s) and
  gpt-oss-20b on a 16 GB card, with config tests and pre-commit hooks.
  Not tagged; recorded here from git history.
