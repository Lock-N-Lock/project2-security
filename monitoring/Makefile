.DEFAULT_GOAL := help
.PHONY: help bootstrap up down restart logs ps

COMPOSE=docker compose --env-file .env --env-file .env.generated -f docker-compose.monitoring.yaml

help:
	@echo ""
	@echo "====================================================="
	@echo "         Lock & Lock Monitoring Commands"
	@echo "====================================================="
	@echo ""
	@echo " [ 최초 설치 ]"
	@echo "  make bootstrap"
	@echo "    - AWS 리소스 자동 조회"
	@echo "    - .env.generated 생성"
	@echo "    - CloudWatch → SNS → Lambda → Telegram 구성"
	@echo "    - Prometheus / Grafana / Loki / Alertmanager 실행"
	@echo "    - Service Discovery 검증"
	@echo ""
	@echo " [ 운영 ]"
	@echo "  make up"
	@echo "    - 모니터링 스택 시작"
	@echo ""
	@echo "  make down"
	@echo "    - 모니터링 스택 종료"
	@echo ""
	@echo "  make restart"
	@echo "    - 모니터링 스택 재시작"
	@echo ""
	@echo "  make logs"
	@echo "    - 모니터링 스택 로그 확인"
	@echo ""
	@echo "  make ps"
	@echo "    - 컨테이너 상태 확인"
	@echo ""

bootstrap:
	@chmod +x bootstrap_monitoring.sh
	bash ./bootstrap_monitoring.sh

up:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) up -d --build --force-recreate --remove-orphans

down:
	$(COMPOSE) down

restart:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) restart

logs:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) logs -f

ps:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) ps