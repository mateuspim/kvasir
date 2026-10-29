# Endpoint

What a client can rely on once `make up` reports the endpoint and
`make status` shows a served model.

## Address and authentication

- Base URL: `http://127.0.0.1:${STRATA_PORT}/v1`, default port `8080`.
  Not reachable from other machines ([ADR 4](../adr/0004-require-a-key-on-loopback.md)).
- Every request needs `Authorization: Bearer <contents of STRATA_KEY_FILE>`.
  Without it the server answers 401.

## Model id

`qwen3.8-flash-next-<MODEL in lower case>`, for example
`qwen3.8-flash-next-q2_0`. `GET /v1/models` lists exactly one entry once the
model is loaded; while it downloads or loads, the port refuses connections or
the list is empty.

## Supported calls

The calls this project uses and checks:

| Call | Used by | Notes |
| --- | --- | --- |
| `GET /v1/models` | `make status`, healthcheck, opencode | One model. |
| `POST /v1/chat/completions` | opencode, `make bench`, `make curl-test` | Streaming with `stream_options.include_usage`, tool calls, images when `VISION` is not `off`. |

Strata also serves an Anthropic-compatible API; this project does not use or
test it. See Strata's documentation for the full surface.

## Limits

| Limit | Value | Set by |
| --- | --- | --- |
| Context | 131,072 tokens at `CONTEXT=128k` | `CONTEXT` |
| Output per request | Clients should cap it; Akita's harness uses 32,768 | client |
| Concurrent requests | Fitted to the card by Strata | `PARALLEL` (not exposed in `.env`) |

Clients that decide when to compact a conversation, such as opencode, should
declare the same context limit ([opencode guide](../guide/opencode.md)).
