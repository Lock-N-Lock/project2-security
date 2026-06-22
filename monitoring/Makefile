# =============================================================
# 파일위치 : ~/project2-security/monitoring/Makefile
# Lock & Lock 팀 프로젝트 monitoring/Makefile
# 사용법: (~/project2-security/monitoring)에서  make [명령어]
# =============================================================
.DEFAULT_GOAL := help
.PHONY: help bootstrap up down restart logs ps destroy teardown teardown-force

COMPOSE=docker compose --env-file .env --env-file .env.generated -f docker-compose.monitoring.yaml
# bootstrap 이 Terraform 밖에서 만든 AWS 리소스(Lambda/IAM/Alarm/구독) 정리
TEARDOWN_SCRIPT=lambda/cloudwatch-telegram-notifier/teardown_cloudwatch_telegram_lambda.sh

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
	@echo "  make destroy"
	@echo "    - 모니터링 스택 종료 및 볼륨 삭제"
	@echo ""

bootstrap:
	@chmod +x bootstrap_monitoring.sh
	bash ./bootstrap_monitoring.sh
	@echo ""
	@echo "ℹ️  참고: nginx 로그 메트릭(:9105)은 이 타깃에 포함되지 않습니다 (별도 sudo 권한 필요)."
	@echo "    전체 구성은 프로젝트 루트에서 'make monitoring-service' 또는 'make full-service'를 실행하세요."

up:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) up -d --build --force-recreate --remove-orphans

down:
	@if [ -f .env.generated ]; then \
		$(COMPOSE) down; \
	else \
		echo "[WARN] .env.generated 파일이 없습니다. 기본 env로 모니터링 스택 정리를 시도합니다."; \
		docker compose --env-file .env -f docker-compose.monitoring.yaml down; \
	fi

restart:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) restart

logs:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) logs -f

ps:
	@test -f .env.generated || (echo "[ERROR] .env.generated 파일이 없습니다. 먼저 make bootstrap을 실행하세요."; exit 1)
	$(COMPOSE) ps

destroy:
	@if [ -f .env.generated ]; then \
		$(COMPOSE) down -v --remove-orphans; \
	else \
		echo "[WARN] .env.generated 파일이 없습니다. 기본 env로 모니터링 스택 정리를 시도합니다."; \
		docker compose --env-file .env -f docker-compose.monitoring.yaml down -v --remove-orphans; \
	fi

teardown:        ## 삭제 대상만 표시 (dry-run, 안전)
	@chmod +x $(TEARDOWN_SCRIPT)
	bash $(TEARDOWN_SCRIPT)

teardown-force:  ## 실제 삭제 (--force)
	@chmod +x $(TEARDOWN_SCRIPT)
	bash $(TEARDOWN_SCRIPT) --force