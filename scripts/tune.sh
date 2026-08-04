#!/usr/bin/env bash
# Sweep speculative-decoding draft depth and report the fastest setting.
#
# This does NOT tune --n-cpu-moe. llama.cpp's common_fit_params computes the
# GPU/CPU split itself at load time and gets it right, but only if neither
# --n-gpu-layers nor --n-cpu-moe is set (it logs "already set by user, abort"
# and gives up). So the split is not a knob here; draft depth is.
#
# Draft depth is genuinely hardware-dependent and not monotonic -- past the
# peak, rejected drafts cost more than accepted ones save, and deep settings
# can end up slower than no speculation at all.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null  # .env is user-created at runtime
[ -f "${REPO_DIR}/.env" ] && source "${REPO_DIR}/.env"
MODELS_DIR="${MODELS_DIR:-/mnt/FastGames/llm-models}"
IMAGE="${IMAGE:-ghcr.io/mostlygeek/llama-swap:cuda}"
PORT=8099
CONTAINER=llama-tune

MODEL="${MODEL:-Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
CTX="${CTX:-131072}"
SPEC="${SPEC:---spec-type draft-mtp}"
SWEEP="${SWEEP:-1 2 3 4 6}"
PROMPT="${PROMPT:-Write a Python function that merges two sorted lists. Include type hints and a docstring.}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[ -f "${MODELS_DIR}/${MODEL}" ] || { red "missing ${MODELS_DIR}/${MODEL}"; exit 1; }

# --- the guard -------------------------------------------------------------
# A contending process does not cause an error, it silently forces tensors onto
# the CPU and produces numbers 3-8x too low that still look plausible. Refuse
# to measure at all unless the GPU is idle.
require_free_gpu() {
  local used
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
  if [ "$used" -gt 500 ]; then
    red "GPU has ${used} MiB in use -- refusing to benchmark."
    red "Stop everything holding VRAM first:  make down && docker ps | grep llama"
    exit 1
  fi
}

require_free_gpu
ylw "Model:  ${MODEL}"
ylw "Spec:   ${SPEC}   ctx=${CTX}"
printf '\n%-10s %-12s %-12s %s\n' 'n_max' 'gen tok/s' 'accept %' 'verdict'
printf '%.0s-' {1..48}; printf '\n'

best_n=''; best_ts=0
for n in $SWEEP; do
  cleanup; sleep 2; require_free_gpu

  # shellcheck disable=SC2086
  docker run -d --name "$CONTAINER" --gpus all \
    -v "${MODELS_DIR}:/models:ro" -p "127.0.0.1:${PORT}:${PORT}" \
    --entrypoint /app/llama-server "$IMAGE" \
    --host 0.0.0.0 --port "$PORT" --jinja --flash-attn on \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --model "/models/${MODEL}" --ctx-size "$CTX" \
    ${SPEC} --spec-draft-n-max "$n" ${SPEC_EXTRA:-} >/dev/null

  ok=0
  for _ in $(seq 1 40); do
    curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1 && { ok=1; break; }
    docker ps -q -f "name=${CONTAINER}" | grep -q . || break
    sleep 3
  done
  [ "$ok" = 1 ] || { printf '%-10s %s\n' "$n" 'failed to load'; continue; }

  # PROMPT must be exported: the python below reads it from the environment
  # rather than being interpolated, so prompts containing quotes stay safe.
  export PROMPT
  body=$(python -c 'import json,os;print(json.dumps({"model":"x","messages":[{"role":"user","content":os.environ["PROMPT"]}],"max_tokens":400}))')

  # REPS matters. A single sample varies by ~10% run to run -- enough to pick
  # the wrong setting outright. A one-shot sweep once reported n_max=3 as best
  # when three repeats showed n_max=2 ahead by 5 tok/s.
  samples=(); accs=()
  for _ in $(seq 1 "${REPS:-3}"); do
    read -r s a < <(curl -s "http://localhost:${PORT}/v1/chat/completions" \
        -H 'Content-Type: application/json' -d "$body" \
      | python -c '
import json,sys
try: t=json.load(sys.stdin).get("timings",{})
except Exception: print("0 0"); raise SystemExit
acc=100*t.get("draft_n_accepted",0)/max(t.get("draft_n",1),1)
print("%.1f %.1f" % (t.get("predicted_per_second",0), acc))')
    samples+=("$s"); accs+=("$a")
  done
  read -r ts acc < <(python -c "
s=[float(x) for x in '${samples[*]}'.split()]
a=[float(x) for x in '${accs[*]}'.split()]
print('%.1f %.1f' % (sum(s)/len(s), sum(a)/len(a)))")

  printf '%-10s %-12s %-12s\n' "$n" "$ts" "$acc"
  awk -v a="$ts" -v b="$best_ts" 'BEGIN{exit !(a>b)}' && { best_ts=$ts; best_n=$n; }
done

printf '\n'
if [ -n "$best_n" ]; then
  grn "Best: --spec-draft-n-max ${best_n} at ${best_ts} tok/s"
  # shellcheck disable=SC2016  # backticks are literal text in help output
  printf 'Set it in config/llama-swap.yaml, then `make restart`.\n'
  printf 'Record the full sweep in CLAUDE.md so the choice stays justified.\n'
else
  red 'Nothing loaded successfully.'
fi
