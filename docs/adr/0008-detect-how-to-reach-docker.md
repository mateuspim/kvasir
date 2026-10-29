# 8. Detect how to reach docker

- Status: Accepted
- Date: 2026-10-29
- Supersedes: [ADR 3](0003-reach-docker-through-pkexec.md)

## Context

[ADR 3](0003-reach-docker-through-pkexec.md) made `pkexec docker` the default
for everyone. That is the maintainer's choice on an Omarchy desktop, where the
user is deliberately not in the `docker` group and polkit is available. It is
wrong as a default for others: people already in the `docker` group or running
rootless docker get a needless password prompt on every command, and servers
without polkit have no pkexec at all.

The concern behind ADR 3 still holds: membership in the `docker` group is
root-equivalent, so the project must never push anyone into it.

## Decision

When `DOCKER` is not set in `.env`, the Makefile picks once per run:

1. `docker`, if `docker info` already works for this user;
2. `pkexec docker`, if pkexec is installed;
3. `sudo docker` otherwise.

`make help` prints the choice. Setting `DOCKER` in `.env` forces one. Compose
still gets absolute paths and reads `.env` itself, because pkexec and sudo
both reset the environment.

## Consequences

- Each machine gets the least intrusive way it already supports; nobody is
  told to join the `docker` group.
- The maintainer's setup is unchanged: without docker access, detection lands
  on pkexec.
- Every make run calls `docker info` once, which costs a fraction of a second
  and fails fast without a daemon.
- `.env` paths must stay absolute, and `make test` keeps checking it.
