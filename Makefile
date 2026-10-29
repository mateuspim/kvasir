.DEFAULT_GOAL := help

.PHONY: help key up down restart logs status pull plan bench curl-test du shell test lint

-include .env
export

# Docker runs through pkexec: this user is deliberately NOT in the docker group
# (membership is root-equivalent). pkexec drops the environment, so compose is
# given absolute paths and reads its variables from .env, never from the shell.
DOCKER          ?= pkexec docker
COMPOSE         := $(DOCKER) compose --project-directory $(CURDIR) \
                     --env-file $(CURDIR)/.env -f $(CURDIR)/docker-compose.yml
STRATA_PORT     ?= 8080
STRATA_KEY_FILE ?= $(HOME)/.config/local-llm/strata.key
STRATA_IMAGE    ?= ghcr.io/niko1221/strata:0.2.7-cuda13
ENDPOINT        := http://127.0.0.1:$(STRATA_PORT)
AUTH             = -H "Authorization: Bearer $$(cat $(STRATA_KEY_FILE))"

help:
	@printf '%s\n' 'strata helper targets:'
	@printf '  %-14s %s\n' \
	  'key'        'Create the API key file (once; never overwrites)' \
	  'up'         'Start the stack (first start downloads ~72 GB)' \
	  'down'       'Stop the stack' \
	  'restart'    'Recreate the container (after .env edits)' \
	  'logs'       'Follow Strata logs' \
	  'status'     'GPU/RAM use and the model the endpoint serves' \
	  'pull'       'Pull the pinned image' \
	  'plan'       'Dry run: what MODEL/CONTEXT would download, changes nothing' \
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

key:
	@test -s $(STRATA_KEY_FILE) && echo "exists: $(STRATA_KEY_FILE)" || { \
	  mkdir -p $(dir $(STRATA_KEY_FILE)) && chmod 700 $(dir $(STRATA_KEY_FILE)) && \
	  (umask 077; openssl rand -hex 24 | tr -d '\n' > $(STRATA_KEY_FILE)) && \
	  echo "created: $(STRATA_KEY_FILE)"; }

up:
	@test -f .env || { echo 'no .env: cp .env.example .env'; exit 1; }
	@test -s $(STRATA_KEY_FILE) || { echo 'no key file: make key'; exit 1; }
	$(COMPOSE) up -d
	@echo "Endpoint: $(ENDPOINT)/v1  (first start: watch with make logs)"

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) up -d --force-recreate

logs:
	$(COMPOSE) logs -f strata

status:
	@echo '--- GPU ---'
	@nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu \
	   --format=csv,noheader
	@echo '--- RAM ---'
	@free -g | sed -n 2p
	@echo '--- served model ---'
	@curl -sf $(AUTH) $(ENDPOINT)/v1/models | python -c \
	   'import json,sys; [print(" ",m["id"]) for m in json.load(sys.stdin)["data"]]' \
	   2>/dev/null || echo '  (not serving yet)'

pull:
	$(DOCKER) pull $(STRATA_IMAGE)

plan:
	$(DOCKER) run --rm --gpus all -v $(STRATA_DATA_DIR):/data $(STRATA_IMAGE) \
	  strata launch --plan --family $(FAMILY) --model $(MODEL) \
	  --context $(CONTEXT) --data-dir /data/Strata-data

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
	  | python -m json.tool

du:
	@du -sh $(STRATA_DATA_DIR)/Strata-data/* 2>/dev/null || echo 'no model data yet'

shell:
	$(COMPOSE) exec strata /bin/sh
