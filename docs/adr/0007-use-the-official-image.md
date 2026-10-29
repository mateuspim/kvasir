# 7. Run the official image, not a host install

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

Strata can be installed on the host in several ways: the project's
`install.sh` (checksum plus a signed-feed check), a GitHub release through
mise, or third-party AUR packages (`strata-terminal-bin`, which skips the
signature check, and source builds). Any host install then downloads its GPU
engine and model into the user's home on first launch. The name also
collides with an unrelated `strata` file manager in Arch and Omarchy repos.

Strata also publishes official images that bundle the Terminal and one engine
package, verified at build time.

## Decision

Run the official image through compose. Do not script any host install.

## Consequences

- Nothing is installed on the host; removing the stack is `make down` and
  deleting the data directory.
- The engine version is tied to the image tag ([ADR 6](0006-pin-the-image-tag.md)).
- Akita's benchmark drivers start Strata with `strata serve --config` from a
  host install. Here the canaries are pointed at the running container instead
  ([benchmarks guide](../guide/benchmarks.md)).
- `strata` commands inside the container are reached with `make shell` or
  `$(DOCKER) exec strata strata …`.
