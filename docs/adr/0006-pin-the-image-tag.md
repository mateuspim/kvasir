# 6. Pin the image to a release tag

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

Strata publishes `ghcr.io/niko1221/strata:<version>-<flavor>` and a floating
`latest-<flavor>`. With a floating tag, a pull or a host reboot with a fresh
pull can change the engine under a saved preset, and speed or behaviour can
change with nothing in this repo showing why. Strata releases often: 0.2.5 to
0.2.7 in a few days.

## Decision

Pin the image to a release tag, currently `0.2.7-cuda13`, in both the compose
default and `.env.example`. Upgrading means editing `STRATA_IMAGE`, then
`make pull` and `make restart`.

## Consequences

- Each engine change is a visible commit or `.env` edit, so a regression can
  be traced and rolled back.
- On upgrade, the entrypoint drops saved run settings that name an engine
  folder the new image lacks and rebuilds them from the kept model files,
  without downloading again.
- Security fixes in Strata arrive only when someone bumps the tag.
- `make test` checks both places, because `.env.example` overrides the compose
  default and a check of the rendered file alone would miss a floating default.
