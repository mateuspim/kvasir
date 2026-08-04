#!/usr/bin/env bash
# Config test suite. Fast, offline, no GPU -- safe to run as a pre-commit hook.
#
# The point of these tests is to catch the failure modes this project has
# actually hit, not hypothetical ones:
#
#   - a model advertised in llama-swap.yaml whose weights are not on disk
#     (llama-swap happily starts, then returns 500s to anything asking for it)
#   - a filename typo'd from the repo name, e.g. writing
#     Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL.gguf when the -MTP- repo ships files with
#     no MTP infix at all
#   - --n-gpu-layers / --n-cpu-moe creeping back in, which makes llama.cpp
#     abandon its own memory fitting and OOM at this context length
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null  # .env is user-created at runtime
[ -f "${REPO_DIR}/.env" ] && source "${REPO_DIR}/.env"
MODELS_DIR="${MODELS_DIR:-/mnt/FastGames/llm-models}"
CFG="${REPO_DIR}/config/llama-swap.yaml"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
info() { printf '  \033[33m ..  \033[0m %s\n' "$*"; }

echo "config tests"

# --- 1. YAML parses and has the expected shape -----------------------------
if python -c "
import yaml,sys
d=yaml.safe_load(open('$CFG'))
assert isinstance(d.get('models'),dict) and d['models'], 'no models defined'
" 2>/dev/null; then ok "llama-swap.yaml parses and defines models"
else bad "llama-swap.yaml is invalid or defines no models"; fi

# --- 2. Every referenced weight file exists --------------------------------
# This is the test that matters most. Expand macros first, since the model
# paths can be split across ${server} / ${qwen-coding-sampler}.
missing=$(python - "$CFG" "$MODELS_DIR" <<'PY'
import re,sys,yaml
cfg,models_dir=sys.argv[1],sys.argv[2]
import os
d=yaml.safe_load(open(cfg)) or {}
macros=d.get('macros') or {}
out=[]
for name,m in (d.get('models') or {}).items():
    cmd=m.get('cmd','')
    for k,v in macros.items():
        cmd=cmd.replace('${%s}'%k, str(v))
    for flag in ('--model','--mmproj','--spec-draft-model'):
        for path in re.findall(re.escape(flag)+r'\s+(\S+)', cmd):
            host=path.replace('/models', models_dir.rstrip('/'),1)
            if not os.path.isfile(host):
                out.append(f"{name}: {flag} {path} -> missing {host}")
print('\n'.join(out))
PY
)
if [ -z "$missing" ]; then ok "every model/mmproj/draft file referenced in config exists on disk"
else
  bad "config references files that are not on disk:"
  # Indent via sed rather than word-splitting $missing, which would break on
  # any path containing a space.
  printf '%s\n' "$missing" | sed 's/^/       /'
fi

# --- 3. The auto-fit footgun -----------------------------------------------
if grep -qE '^\s*--(n-gpu-layers|n-cpu-moe|cpu-moe)\b' "$CFG"; then
  bad "config sets --n-gpu-layers/--n-cpu-moe; this disables llama.cpp memory fitting and OOMs at 128K"
else ok "no hard-coded GPU split (llama.cpp auto-fit left intact)"; fi

# --- 4. Shell scripts are syntactically valid ------------------------------
sh_bad=0
for f in "${REPO_DIR}"/scripts/*.sh; do
  bash -n "$f" 2>/dev/null || { bad "shell syntax error in $(basename "$f")"; sh_bad=1; }
done
[ "$sh_bad" = 0 ] && ok "all scripts pass bash -n"

# --- 5. docker-compose is valid and stays on loopback ----------------------
if (cd "$REPO_DIR" && docker compose config >/dev/null 2>&1); then
  ok "docker-compose.yml validates"
  # compose normalises "127.0.0.1:8080:8080" into a host_ip field on its own
  # line, so match that rather than the published port.
  if (cd "$REPO_DIR" && docker compose config 2>/dev/null | grep -qE '^\s*host_ip:\s*127\.0\.0\.1\s*$'); then
    ok "endpoint published on loopback only"
  else
    bad "endpoint is NOT restricted to 127.0.0.1 -- llama-swap has no auth"
  fi
else
  info "docker compose unavailable, skipping compose checks"
fi

# --- 6. models.conf entries are downloadable-looking -----------------------
badurl=$(python - "${REPO_DIR}/models.conf" <<'PY'
import sys
bad=[]
for line in open(sys.argv[1]):
    line=line.split('#',1)[0].strip()
    if not line or line.startswith('[') or '=' not in line:
        continue
    name,url=(p.strip() for p in line.split('=',1))
    if not url.startswith('https://'):
        bad.append(name)
print(' '.join(bad))
PY
)
if [ -z "$badurl" ]; then ok "every enabled models.conf entry has an https URL"
else bad "models.conf entries with bad URLs: $badurl"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
