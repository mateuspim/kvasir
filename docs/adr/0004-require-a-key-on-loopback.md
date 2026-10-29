# 4. Require an API key, passed as a secret, on loopback only

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

An inference endpoint runs arbitrary prompts on your GPU. llama-swap had no
authentication, so the earlier setup relied on publishing to `127.0.0.1` only.
Strata's container listens on every address inside the container and refuses
to start without a key; if none is given it generates one.

Passing the key as `API_KEY` would put it in `.env`, the rendered compose
file, `docker inspect` output and process listings.

## Decision

Publish on `127.0.0.1` only, and keep a key anyway. The key lives in a single
file, mode 0600, outside the repo (`STRATA_KEY_FILE`, created by `make key`).
Compose mounts it as the secret `strata_key`, and the container reads it
through `API_KEY_FILE=/run/secrets/strata_key`. Clients such as opencode read
the same file.

## Consequences

- Another local user or process cannot use the endpoint without the file.
- Exposing the endpoint to a LAN later is a one-line port change with
  authentication already in place, but should still be a deliberate choice.
- `make test` fails if the publish leaves loopback, if `API_KEY` is set
  directly in compose or `.env.example`, or if the key file is not mode 600.
