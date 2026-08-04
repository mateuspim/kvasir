.DEFAULT_GOAL := help

.PHONY: help up down restart logs status pull models tune bench shell curl-test du clean test lint

-include .env
export

MODELS_DIR    ?= /mnt/FastGames/llm-models
LLAMA_SWAP_PORT ?= 8080
IMAGE         ?= ghcr.io/mostlygeek/llama-swap:cuda
ENDPOINT      := http://localhost:$(LLAMA_SWAP_PORT)

help:
	@printf '%s\n' 'llama-swap helper targets:'
	@printf '  %-14s %s\n' \
	  'up'         'Start the stack (detached)' \
	  'down'       'Stop the stack' \
	  'restart'    'Recreate the container (after config edits)' \
	  'logs'       'Follow llama-swap logs' \
	  'status'     'Show container state, GPU use, and loaded models' \
	  'pull'       'Pull the latest llama-swap:cuda image' \
	  'models'     'Download every enabled model in models.conf' \
	  'du'         'Show disk used by downloaded models' \
	  'tune'       'Sweep --n-cpu-moe and MTP draft depth, report the optimum' \
	  'bench'      'Benchmark the primary model at current settings' \
	  'curl-test'  'Send a tool-calling request end to end' \
	  'test'       'Run config tests (fast, offline, no GPU)' \
	  'lint'       'Run every pre-commit hook over all files' \
	  'shell'      'Open a shell inside the container'

test:
	@chmod +x scripts/test_config.sh
	@./scripts/test_config.sh

lint:
	@pre-commit run --all-files

up:
	docker compose up -d
	@echo "Endpoint: $(ENDPOINT)/v1  ->  models: $(ENDPOINT)/v1/models"

down:
	docker compose down

restart:
	docker compose up -d --force-recreate

logs:
	docker compose logs -f llama-swap

status:
	@docker compose ps
	@echo '--- GPU ---'
	@nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu \
	   --format=csv,noheader
	@echo '--- models known to llama-swap ---'
	@curl -s $(ENDPOINT)/v1/models | python -c \
	   'import json,sys; [print(" ",m["id"]) for m in json.load(sys.stdin)["data"]]' \
	   2>/dev/null || echo '  (not running)'

pull:
	docker pull $(IMAGE)

models:
	@chmod +x scripts/fetch_models.sh
	@./scripts/fetch_models.sh

du:
	@du -sh $(MODELS_DIR) 2>/dev/null || echo 'no models yet'
	@ls -lh $(MODELS_DIR)/*.gguf 2>/dev/null | awk '{printf "  %-46s %s\n", $$9, $$5}' || true

tune:
	@chmod +x scripts/tune.sh
	@./scripts/tune.sh

# Raw benchmark of the primary model, bypassing llama-swap.
# NOTE: this image ships the unified `llama` CLI, not a standalone llama-bench.
bench:
	docker run --rm --gpus all -v $(MODELS_DIR):/models:ro \
	  --entrypoint /app/llama $(IMAGE) bench \
	  -m /models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
	  -ngl 999 -ncmoe 18 -fa on -p 512 -n 128

# Exercises the path that actually matters for agents: tool calling over the
# OpenAI-compatible endpoint. A model that chats fine can still fail here.
curl-test:
	@curl -s $(ENDPOINT)/v1/chat/completions \
	  -H 'Content-Type: application/json' \
	  -d '{"model":"qwen3.6-35b","messages":[{"role":"user","content":"What is 17*23? Use the calculator tool."}],"tools":[{"type":"function","function":{"name":"calculator","description":"Evaluate an arithmetic expression","parameters":{"type":"object","properties":{"expr":{"type":"string"}},"required":["expr"]}}}]}' \
	  | python -m json.tool

shell:
	docker compose exec llama-swap /bin/sh

clean:
	docker compose down -v
