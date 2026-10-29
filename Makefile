.DEFAULT_GOAL := help

.PHONY: help env key preflight up down restart logs status pull plan bench curl-test du shell test lint

-include .env
export

# pkexec by default: joining the docker group is root-equivalent (docs/adr/0003).
# pkexec drops the environment, so compose is given absolute paths and reads its
# variables from .env, never from the shell. Override DOCKER in .env.
DOCKER          ?= pkexec docker
GPU_VENDOR      ?= nvidia
COMPOSE         := $(DOCKER) compose --project-directory $(CURDIR) \
                     --env-file $(CURDIR)/.env -f $(CURDIR)/docker-compose.yml \
                     -f $(CURDIR)/compose/$(GPU_VENDOR).yml
STRATA_PORT     ?= 8080
STRATA_KEY_FILE ?= $(HOME)/.config/local-llm/strata.key
STRATA_IMAGE    ?= ghcr.io/niko1221/strata:0.2.7-cuda13
ENDPOINT        := http://127.0.0.1:$(STRATA_PORT)
AUTH             = -H "Authorization: Bearer $$(cat $(STRATA_KEY_FILE))"

help:
	@printf '%s\n' 'local-llm-stack targets:'
	@printf '  %-14s %s\n' \
	  'env'        'Create .env for this machine (never overwrites)' \
	  'key'        'Create the API key file (never overwrites)' \
	  'plan'       'Dry run: what MODEL/CONTEXT would download, changes nothing' \
	  'up'         'Start the stack (first start downloads ~72 GB)' \
	  'down'       'Stop the stack' \
	  'restart'    'Recreate the container (after .env edits)' \
	  'logs'       'Follow Strata logs' \
	  'status'     'GPU/RAM use and the model the endpoint serves' \
	  'pull'       'Pull the pinned image' \
	  'bench'      'Speed canary: cold ~5K and ~41K prompts, 256 tokens out' \
	  'curl-test'  'Send a tool-calling request end to end' \
	  'du'         'Show disk used by model data' \
	  'test'       'Run config tests (fast, offline, no GPU)' \
	  'lint'       'Run every pre-commit hook over all files' \
	  'shell'      'Open a shell inside the container'

test:
	@./scripts/test_config.sh

lint:
	@pre-commit run --all-files

env:
	@if [ -f .env ]; then echo '.env exists; not overwriting'; else \
	  sed -e 's|^STRATA_KEY_FILE=.*|STRATA_KEY_FILE=$(HOME)/.config/local-llm/strata.key|' \
	      -e "s|^RENDER_GID=.*|RENDER_GID=$$(getent group render | cut -d: -f3)|" \
	      .env.example > .env && \
	  echo 'wrote .env -- now set STRATA_DATA_DIR to an absolute path on NVMe'; fi

key:
	@test -s $(STRATA_KEY_FILE) && echo "exists: $(STRATA_KEY_FILE)" || { \
	  mkdir -p $(dir $(STRATA_KEY_FILE)) && chmod 700 $(dir $(STRATA_KEY_FILE)) && \
	  (umask 077; openssl rand -hex 24 | tr -d '\n' > $(STRATA_KEY_FILE)) && \
	  echo "created: $(STRATA_KEY_FILE)"; }

# Checks that turn a confusing compose or engine error into a plain one.
preflight:
	@test -f .env || { echo 'no .env: make env'; exit 1; }
	@test -s $(STRATA_KEY_FILE) || { echo 'no key file: make key'; exit 1; }
	@test -d $(STRATA_DATA_DIR) || { echo 'STRATA_DATA_DIR does not exist: $(STRATA_DATA_DIR)'; exit 1; }

up: preflight
	$(COMPOSE) up -d
	@echo "Endpoint: $(ENDPOINT)/v1  (first start: watch with make logs)"

down:
	$(COMPOSE) down

restart: preflight
	$(COMPOSE) up -d --force-recreate

logs:
	$(COMPOSE) logs -f strata

status:
	@echo '--- GPU ---'
	@nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu \
	   --format=csv,noheader 2>/dev/null || echo '  (nvidia-smi unavailable)'
	@echo '--- RAM ---'
	@free -g | sed -n 2p
	@echo '--- served model ---'
	@curl -sf $(AUTH) $(ENDPOINT)/v1/models | python3 -c \
	   'import json,sys; [print(" ",m["id"]) for m in json.load(sys.stdin)["data"]]' \
	   2>/dev/null || echo '  (not serving yet)'

pull:
	$(DOCKER) pull $(STRATA_IMAGE)

# Runs through compose so the plan sees the same GPU, volume and image as `up`.
plan: preflight
	$(COMPOSE) run --rm --no-deps strata strata launch --plan --family $(FAMILY) \
	  --model $(MODEL) --context $(CONTEXT) --data-dir /data/Strata-data

# The filler is repetitive code, which MTP drafts unusually well: treat decode
# figures as an upper bound for real agent work.
bench:
	@KEY=$$(cat $(STRATA_KEY_FILE)) python3 scripts/speed.py 200 2800 2800 22000 22000

# Exercises the path that actually matters for agents: tool calling over the
# OpenAI-compatible endpoint. A model that chats fine can still fail here.
curl-test:
	@curl -s $(AUTH) $(ENDPOINT)/v1/chat/completions \
	  -H 'Content-Type: application/json' \
	  -d '{"model":"qwen3.8-flash-next-$(shell echo $(MODEL) | tr A-Z a-z)","messages":[{"role":"user","content":"What is 17*23? Use the calculator tool."}],"tools":[{"type":"function","function":{"name":"calculator","description":"Evaluate an arithmetic expression","parameters":{"type":"object","properties":{"expr":{"type":"string"}},"required":["expr"]}}}]}' \
	  | python3 -m json.tool

du:
	@du -sh $(STRATA_DATA_DIR)/Strata-data/* 2>/dev/null || echo 'no model data yet'

shell:
	$(COMPOSE) exec strata /bin/sh
