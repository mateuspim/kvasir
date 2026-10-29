#!/usr/bin/env bash
# Config test suite. Fast, offline, no GPU, no docker daemon -- safe to run as
# a pre-commit hook. `docker compose config` only renders the file client-side.
#
# The point of these tests is to catch the failure modes this setup can
# actually hit, not hypothetical ones:
#
#   - the endpoint published beyond loopback
#   - the API key pasted into compose or .env, where `docker inspect` and git
#     can see it, instead of the secret file
#   - the image drifting to a floating tag (latest-*), so a restart silently
#     changes the engine under a tuned preset
#   - model data put in a named volume, which lands ~105 GB on the root disk
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"
# Render against the example so the suite runs on a fresh clone with no .env.
ENV_FILE="${REPO_DIR}/.env.example"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
info() { printf '  \033[33m ..  \033[0m %s\n' "$*"; }

echo "config tests"

# --- 1. compose renders, and the rendered result is what we expect ---------
rendered=""
if command -v docker >/dev/null 2>&1; then
  rendered=$(docker compose --project-directory "$REPO_DIR" --env-file "$ENV_FILE" \
               -f "$COMPOSE_FILE" config --format json 2>/dev/null) || rendered=""
fi

if [ -n "$rendered" ]; then
  ok "docker-compose.yml validates"
  # Query the normalised JSON rather than grepping YAML, whose layout compose
  # is free to change between versions.
  check() { printf '%s' "$rendered" | python3 -c "import json,sys; s=json.load(sys.stdin)['services']['strata']; sys.exit(0 if ($1) else 1)"; }

  if check "all(p.get('host_ip') == '127.0.0.1' for p in s.get('ports', []))"; then
    ok "endpoint published on loopback only"
  else bad "endpoint is NOT restricted to 127.0.0.1"; fi

  if check "any(v['target'] == '/data' and v['type'] == 'bind' for v in s.get('volumes', []))"; then
    ok "/data is a bind mount (model stays off the root disk)"
  else bad "/data is not a bind mount -- a named volume puts ~105 GB on /"; fi
else
  info "docker compose unavailable, skipping compose checks"
fi

# --- 2. the image is pinned, both as the compose default and in .env.example
# (.env.example overrides the default, so a check of the rendered file alone
# would miss a floating default)
unpinned=$( { sed -n 's/.*STRATA_IMAGE:-\([^}]*\)}.*/\1/p' "$COMPOSE_FILE"
              sed -n 's/^STRATA_IMAGE=//p' "$ENV_FILE"; } \
            | grep -vE ':[0-9]+\.[0-9]+\.[0-9]+-' )
if [ -z "$unpinned" ]; then ok "image pinned to a release tag in compose and .env.example"
else bad "image not pinned to a release tag: $unpinned"; fi

# --- 3. the key only ever comes from the secret file ------------------------
if grep -qE '^\s*API_KEY\s*:' "$COMPOSE_FILE" || grep -qE '^\s*API_KEY=' "$ENV_FILE"; then
  bad "API_KEY is set directly; use STRATA_KEY_FILE (compose secret) instead"
elif grep -qE 'API_KEY_FILE:\s*/run/secrets/' "$COMPOSE_FILE"; then
  ok "API key passed as a compose secret, not an env var"
else bad "compose does not read the key from /run/secrets"; fi

# --- 4. the local .env, if there is one, is usable through pkexec -----------
if [ -f "${REPO_DIR}/.env" ]; then
  # Read raw values: sourcing would expand ~ and hide exactly the mistake
  # this check exists for.
  for var in STRATA_DATA_DIR STRATA_KEY_FILE; do
    val=$(sed -n "s/^${var}=//p" "${REPO_DIR}/.env" | tail -1)
    printf -v "$var" '%s' "$val"
    case "$val" in
      /*) ok "$var is absolute" ;;
      *)  bad "$var must be an absolute path (pkexec does not expand ~ or \$HOME): '$val'" ;;
    esac
  done
  if [ -f "${STRATA_KEY_FILE:-}" ]; then
    mode=$(stat -c '%a' "$STRATA_KEY_FILE")
    [ "$mode" = 600 ] && ok "key file is mode 600" || bad "key file is mode $mode, want 600"
  else info "no key file yet (make key)"; fi
else
  info "no .env yet, skipping local checks (cp .env.example .env)"
fi

# --- 5. scripts are syntactically valid -------------------------------------
sh_bad=0
for f in "${REPO_DIR}"/scripts/*.sh; do
  bash -n "$f" 2>/dev/null || { bad "shell syntax error in $(basename "$f")"; sh_bad=1; }
done
for f in "${REPO_DIR}"/scripts/*.py; do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null \
    || { bad "python syntax error in $(basename "$f")"; sh_bad=1; }
done
[ "$sh_bad" = 0 ] && ok "all scripts parse"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
