# Connect opencode

[opencode](https://opencode.ai) reads providers from
`~/.config/opencode/opencode.json`. This repo does not write that file; add
the provider yourself.

## Provider

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "strata": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Strata (local)",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "{file:~/.config/kvasir/strata.key}"
      },
      "models": {
        "qwen3.8-flash-next-q2_0": {
          "name": "Qwen3.8 Flash-Next Q2_0",
          "tool_call": true,
          "reasoning": true,
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 131072, "output": 32768 }
        }
      }
    }
  }
}
```

Merge it into your existing config rather than replacing the file. Then:

```sh
opencode run -m strata/qwen3.8-flash-next-q2_0 "Create hello.py that prints the 10th Fibonacci number and run it."
```

## Why each setting is there

- **`{file:…}` for the key** keeps the key out of the config file. Point it at
  your `STRATA_KEY_FILE`.
- **`limit.context` matches `CONTEXT`** (131072 for `128k`). opencode decides
  when to compact from this number; if it is wrong, it compacts too early or
  overruns the server.
- **`attachment: true` and the image modality** are needed for vision,
  separately from `VISION=on` on the server. Without them opencode never sends
  the image and the model replies that it cannot see images.
- **The model id follows `MODEL`.** After switching to IQ3_XXS, the id is
  `qwen3.8-flash-next-iq3_xxs`.

## Other clients

Anything that speaks the OpenAI chat API works with the same base URL, key and
model id. Use `make curl-test` to check tool calling end to end before blaming
the client.
