# 3. Reach docker through pkexec, not the docker group

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

Talking to the docker daemon needs either root or membership in the `docker`
group. Membership is root-equivalent: any member can start a container that
mounts `/` read-write. Adding a desktop user to it to save a password prompt
trades away the boundary sudo and polkit exist for.

## Decision

The Makefile invokes docker as `$(DOCKER)`, default `pkexec docker`. Because
pkexec resets the environment, compose is always given absolute
`--project-directory`, `--env-file` and `-f` paths and reads every variable
from `.env`. `DOCKER` can be set in `.env` (for example `sudo docker`) for
machines without polkit.

## Consequences

- Each docker-touching target asks for authentication. Targets that need no
  docker (`status`, `bench`, `curl-test`, `test`) talk to the endpoint or read
  files directly so they never prompt.
- `.env` paths must be absolute; `~` and `$HOME` do not expand under pkexec.
  `make test` fails on a relative path, and `make env` writes absolute ones.
- Agents and docs must never suggest joining the `docker` group.
