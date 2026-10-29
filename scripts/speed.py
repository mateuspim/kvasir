#!/usr/bin/env python3
"""Akita-style speed canary: cold prompt of N tokens, 256 generated, streamed timing."""
import json, os, sys, time, urllib.request, uuid

KEY = os.environ["KEY"]
URL = f"http://127.0.0.1:{os.environ.get('STRATA_PORT', '8080')}/v1/chat/completions"
MODEL = "qwen3.8-flash-next-" + os.environ.get("MODEL", "Q2_0").lower()

def filler(words):
    base = ("def process(items):\n    total = 0\n    for i, x in enumerate(items):\n"
            "        if x % 3 == 0:\n            total += x * i\n    return total\n")
    out, n = [], 0
    while n < words:
        out.append(base); n += len(base.split())
    return "".join(out)

def run(target_words):
    prompt = f"nonce {uuid.uuid4()}\n" + filler(target_words) + \
        "\nExplain in detail what the code above does, line by line."
    body = json.dumps({"model": MODEL, "stream": True, "max_tokens": 256, "temperature": 0,
                       "stream_options": {"include_usage": True},
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(URL, body, {"Content-Type": "application/json",
                                             "Authorization": "Bearer " + KEY})
    t0 = time.time(); first = None; usage = {}; chunks = 0
    with urllib.request.urlopen(req, timeout=900) as r:
        for line in r:
            line = line.strip()
            if not line.startswith(b"data:") or line == b"data: [DONE]":
                continue
            d = json.loads(line[5:])
            if d.get("usage"):
                usage = d["usage"]
            for c in d.get("choices", []):
                delta = c.get("delta", {})
                if delta.get("content") or delta.get("reasoning_content"):
                    chunks += 1
                    if first is None:
                        first = time.time()
    t1 = time.time()
    pt, ct = usage.get("prompt_tokens", 0), usage.get("completion_tokens", chunks)
    ttft = first - t0
    print(f"prompt {pt:>6} tok | TTFT {ttft:6.1f}s | prefill {pt/ttft:7.0f} tok/s | "
          f"decode {ct/(t1-first):6.1f} tok/s ({ct} tok)", flush=True)

for w in map(int, sys.argv[1:]):
    run(w)
