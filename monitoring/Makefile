.PHONY: help bootstrap up down restart logs ps

COMPOSE=docker compose --env-file .env -f docker-compose.monitoring.yaml

help:
	@echo "make bootstrap"
	@echo "make up"
	@echo "make down"

bootstrap:
	bash ./bootstrap_monitoring.sh

up:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap 을 실행하세요."; exit 1)
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps