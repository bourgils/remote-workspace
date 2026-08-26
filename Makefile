IMAGE ?= remote-workspace:local

.PHONY: build up down logs validate
build:
	docker build -t $(IMAGE) .

up:
	WORKSPACE_RUNTIME_IMAGE=$(IMAGE) docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f workspace

validate:
	python3 scripts/validate.py
