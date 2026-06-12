.PHONY: help bootstrap up down restart logs ps

COMPOSE=docker compose --env-file .env -f docker-compose.monitoring.yaml

help:
	@echo "make bootstrap"
	@echo "make up"
	@echo "make down"

bootstrap:
	bash ./bootstrap_monitoring.sh

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps