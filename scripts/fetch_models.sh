#!/usr/bin/env bash
# Download every enabled entry in models.conf into $MODELS_DIR.
# Idempotent: existing files of the expected size are skipped, partial
# downloads are resumed. Safe to re-run and safe to interrupt.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${REPO_DIR}/models.conf"
# shellcheck source=/dev/null  # .env is user-created at runtime
[ -f "${REPO_DIR}/.env" ] && source "${REPO_DIR}/.env"
MODELS_DIR="${MODELS_DIR:-/mnt/FastGames/llm-models}"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }

[ -f "$CONF" ] || { red "missing $CONF"; exit 1; }
mkdir -p "$MODELS_DIR"

# Refuse to start a multi-GB download that cannot finish.
avail_gb=$(df -BG --output=avail "$MODELS_DIR" | tail -1 | tr -dc '0-9')
ylw "Target: ${MODELS_DIR} (${avail_gb} GB free)"

declare -a auth=()
[ -n "${HF_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${HF_TOKEN}")

while IFS= read -r line; do
  # Strip inline comments, skip blanks / comments / section headers.
  line="${line%%#*}"
  line="$(printf '%s' "$line" | sed 's/[[:space:]]*$//')"
  [[ -z "$line" || "$line" =~ ^\[ ]] && continue
  [[ "$line" != *=* ]] && continue

  fname="$(printf '%s' "${line%%=*}" | xargs)"
  url="$(printf '%s' "${line#*=}" | xargs)"
  dest="${MODELS_DIR}/${fname}"

  remote_size=$(curl -sIL "${auth[@]}" "$url" \
    | grep -i '^content-length:' | tail -1 | tr -dc '0-9' || true)

  if [ -f "$dest" ]; then
    local_size=$(stat -c%s "$dest")
    if [ -n "$remote_size" ] && [ "$local_size" = "$remote_size" ]; then
      grn "ok    ${fname}"
      continue
    fi
    ylw "resume ${fname} (${local_size}/${remote_size:-?} bytes)"
  else
    ylw "get   ${fname} ($(( ${remote_size:-0} / 1000000000 )) GB)"
  fi

  # -C - resumes; --retry survives the transient 5xx HF throws under load.
  # --no-progress-meter because this is usually run non-interactively (make,
  # background job) where curl's meter produces megabytes of carriage-return
  # spam in the log. Progress is reported per-file by the lines above.
  curl -fL --retry 5 --retry-delay 5 --retry-all-errors --no-progress-meter \
       -C - "${auth[@]}" -o "$dest" "$url" \
    || { red "failed ${fname}"; exit 1; }
  grn "done  ${fname}"
done < "$CONF"

grn "All enabled models present in ${MODELS_DIR}"
du -sh "$MODELS_DIR"
