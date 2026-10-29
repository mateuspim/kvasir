# Development runbook

## Set up

```sh
git clone https://github.com/mateuspim/kvasir
cd kvasir
make env            # .env with this machine's key path and render group
$EDITOR .env        # set STRATA_DATA_DIR
make key
make test
```

`make test` needs neither a GPU nor a running docker daemon: it renders the
compose files client-side with `docker compose config` and checks the result.
Without the docker CLI the compose checks are skipped and reported as such.

## Tests

`scripts/test_config.sh` is the whole suite, run by `make test`, the
pre-commit hook and CI. It renders `docker-compose.yml` with every file in
`compose/` against `.env.example` and checks:

| Check | Guards against |
| --- | --- |
| renders, ports bound to `127.0.0.1` | an override re-publishing the endpoint on the LAN |
| `/data` is a bind mount | ~105 GB landing on the root disk in a named volume |
| the override grants a GPU | a vendor file that silently runs on nothing |
| image pinned in compose and `.env.example` | a floating `latest-*` tag |
| key only via `/run/secrets` | a key in compose or `.env.example` |
| `.env` paths absolute, key file 0600 | `~` under pkexec or sudo; a readable key |
| scripts parse | syntax errors |
| no home paths in tracked files | the owner's paths leaking into the public repo |

When adding a check, break the thing it guards and show the check fails
before trusting it. A check that cannot fail is worth nothing.

## Trying a change against the real stack

```sh
make plan           # what would download; changes nothing
make restart        # recreate with the new .env or compose
make logs           # first start: download, pack build, load
make status
make curl-test      # tool calling end to end
make bench          # GPU otherwise idle
```

Only one `strata` container can exist at a time (`container_name: strata`), so
test from one checkout at a time.

## Upgrading Strata

1. Read the [release notes](https://github.com/Niko1221/Strata/releases).
2. Change the tag in `.env`, `.env.example` and the compose default.
3. `make pull && make restart`. Model files are kept; Strata rebuilds its run
   settings for the new engine.
4. `make curl-test` and `make bench`; record changed numbers in
   `docs/guide/benchmarks.md` and the CHANGELOG.

## Refresh the preview

The README hero is `docs/brand/preview.svg`, rendered to `preview.png` at
3840 × 2160. It has no screen captures: the two terminal cards on the right
are drawn in the SVG from real `make bench` and hard-canary output. Update
their text when the numbers change, then render and look at the result:

```sh
rsvg-convert -o preview.png docs/brand/preview.svg
```

Fonts: JetBrainsMono Nerd Font, falling back to any monospace font. Keep
personal paths, hostnames and keys out of the cards.

## Release

1. Move the `CHANGELOG.md` Unreleased entries under `## X.Y.Z - YYYY-MM-DD`.
2. Check the README and guides cover the change; `make test`.
3. Commit `Release X.Y.Z` and create an annotated tag `vX.Y.Z`.
4. Ask the owner before pushing the commit and tag or publishing a release.
