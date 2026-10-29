# Security

## Reporting a vulnerability

Please report privately through GitHub's
[security advisories](https://github.com/mateuspim/kvasir/security/advisories/new)
rather than a public issue. Include the commit or release, the image tag from
`.env`, steps to reproduce and impact. You can expect a reply within a week.

Vulnerabilities in Strata itself belong upstream at
[Niko1221/Strata](https://github.com/Niko1221/Strata).

## Supported versions

Only the latest release on `master` receives fixes.

## Privilege model

This repository is configuration: a compose file, a Makefile and two scripts.
What runs with which rights:

- **Root on the host:** every `docker` command, through `$(DOCKER)`. The
  default `pkexec docker` asks for authentication each time instead of adding
  you to the `docker` group, which is root-equivalent
  ([ADR 3](docs/adr/0003-reach-docker-through-pkexec.md)).
- **In the container:** the official `ghcr.io/niko1221/strata` image, pinned
  to a release tag. It runs as root inside the container, with access to the
  GPU, the data directory, and the key file mounted read-only as a secret.
- **Reads:** `.env`, the key file, and `STRATA_DATA_DIR`.
- **Writes:** `.env` and the key file (`make env`, `make key`, never
  overwriting), and model data in `STRATA_DATA_DIR` (the container).
- **Network:** the endpoint listens on `127.0.0.1` only and every request
  needs the key ([ADR 4](docs/adr/0004-require-a-key-on-loopback.md)). On first
  start the container downloads model files (~72 GB) from Hugging Face; the
  engine is already inside the image. `scripts/speed.py` talks only to
  `127.0.0.1`.
- **Secrets:** one API key in a 0600 file, outside the repo. It reaches the
  container as a compose secret, so it is not in `.env`, the compose file,
  `docker inspect`, or process arguments. `make test` fails if a key is set
  directly or the file is not mode 600.

Nothing changes your system configuration: no packages, services, groups or
files outside this directory, the key file and the data directory.
