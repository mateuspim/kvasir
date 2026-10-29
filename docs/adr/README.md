# Architecture decision records

These records explain implemented design choices. They were documented from
the current code on 2026-10-29; their date is a documentation date, not a
claim about when the original change landed. For the current component map,
see the [architecture overview](../architecture.md).

| # | Decision | Status |
| --- | --- | --- |
| [1](0001-serve-with-strata.md) | Serve with Strata instead of llama.cpp behind llama-swap | Accepted |
| [2](0002-default-to-flash-next-q2_0.md) | Default to Qwen3.8 Flash-Next Q2_0 | Accepted |
| [3](0003-reach-docker-through-pkexec.md) | Reach docker through pkexec, not the docker group | Accepted |
| [4](0004-require-a-key-on-loopback.md) | Require an API key, passed as a secret, on loopback only | Accepted |
| [5](0005-keep-model-data-on-nvme.md) | Keep model data in a bind-mounted NVMe directory | Accepted |
| [6](0006-pin-the-image-tag.md) | Pin the image to a release tag | Accepted |
| [7](0007-use-the-official-image.md) | Run the official image, not a host install | Accepted |

Add the next number for a new durable choice. Include context, decision, and
consequences. When replacing a decision, mark the old record superseded and
link the new one rather than rewriting history.
