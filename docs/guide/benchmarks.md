# Measure speed and coding quality

Give the GPU to the model alone before measuring. Anything else holding VRAM
pushes experts off the card, and results come out 3-8x too low while still
looking plausible. Close games, other model servers and GPU-heavy browser tabs,
and check `make status`.

## Speed: `make bench`

`scripts/speed.py` follows the method of Akita's speed canary: each prompt is
fresh (a unique nonce defeats the prompt cache), the model writes exactly 256
tokens at temperature 0, and the script reports time to first token, prefill
and decode rates from the streamed response. It sends one ~500-token warm-up,
then two ~5K and two ~41K token prompts.

Measured on 2026-10-29: RTX 4080 16 GB, Ryzen 9 9900X, 60 GB RAM, image
`0.2.7-cuda13` (engine 0.1.52), Q2_0, 128K context, int8 KV, MTP on.

| Prompt | Time to first token | Prefill | Decode |
| --- | --- | --- | --- |
| ~5.3K tokens | 1.6 s | ~3,400 tok/s | 126-131 tok/s |
| ~41K tokens | 11.3 s | ~3,600 tok/s | 113-122 tok/s |

With the model loaded: 15.6 of 16.4 GB VRAM (Strata fills the card with its
expert cache on purpose) and about 36 GB of system RAM.

**Decode is an upper bound.** The filler is repeated code, which the MTP draft
predicts unusually well. Real agent sessions decode slower.

## Coding quality: Akita's hard canary

[`bench/hard_canary.py`](https://github.com/akitaonrails/llm-opensource-benchmark/blob/master/bench/hard_canary.py)
runs opencode for four turns on a payment reconciler inside a bubblewrap
sandbox with no network, then grades the result with 36 hidden tests. Its
first prompt is about 64K tokens of transcript with buried and later-reversed
decisions.

Result here, one run on 2026-10-29: **100/100, 36/36 hidden tests**, 14.8 min
for the four turns, 137 requests, largest prompt ~113K tokens. Akita's RTX 5090
scored the same in 7.1 min (Strata) and 5.5 min (Basalt), three runs each.

### Running it against this endpoint

Read the harness before running it: it executes model-written code, inside
its sandbox. It needs `bwrap`, `socat`, Python 3.11+, and opencode 2.1.4's
native binary at the mise path in `bench/sandbox.py` (or `OPENCODE_BINARY`).

The gateway in `bench/sandbox.py` sends a fixed `Bearer local`. Change it to
read the real key from the environment:

```python
{"Content-Type": "application/json",
 "Authorization": "Bearer " + os.environ.get("BENCH_API_KEY", "local")}
```

The gateway runs on the host side of the sandbox, so the key never enters it.
Then, from the benchmark checkout:

```sh
BENCH_API_KEY=$(cat ~/.config/kvasir/strata.key) python3 bench/hard_canary.py \
  --base-url http://127.0.0.1:8080/v1 --model qwen3.8-flash-next-q2_0 \
  --provider strata-docker --label my-run --output results/hard/my-run
```

`results/hard/my-run/report.json` holds the score, each hidden test, and the
integrity checks. Expect 15-30 minutes on a 16 GB card.
