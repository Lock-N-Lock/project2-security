# =============================================================
# 파일위치 : ~/project2-security/Makefile
# Lock & Lock 팀 프로젝트 Makefile
# 사용법: 레포 루트(~/project2-security)에서  make [명령어]
# =============================================================

#  Makefile을 통해 실행되는 모든 명령이 격리 폴더를 바라보게 합니다.
export DOCKER_CONFIG := $(CURDIR)/.docker_config

# 격리 폴더($(DOCKER_CONFIG))의 config.json에서 Docker Hub 로그인 ID 동적 파싱
DOCKER_USER := $(shell jq -r '.auths["https://index.docker.io/v1/"].auth' $(DOCKER_CONFIG)/config.json 2>/dev/null | base64 -d 2>/dev/null | cut -d: -f1)

DOCKER_USER_FALLBACK :=
ifeq ($(DOCKER_USER),)
  DOCKER_USER := zeongni
  DOCKER_USER_FALLBACK := 1
endif

TF_DIR := infra/terraform
TF_DIR2 := infra/ansible

.PHONY: help setup check init fmt validate plan apply apply-auto output destroy destroy-db clean deploy-db deploy-app service build-push build-push-bootstrap
.PHONY: monitoring-bootstrap monitoring-nginx-logs monitoring-service full-service

help:
	@echo ""
	@echo "====================================================="
	@echo "   Lock & Lock 명령어 (project2-security 에서 실행)"
	@echo "====================================================="
	@echo ""
	@echo "  [ 초기 설정 ]"
	@echo "  make setup       AWS CLI + Terraform + Ansible + Docker 설치"
	@echo "  make check       환경·자격증명·Docker 상태 확인"
	@echo ""
	@echo "  [ Terraform ]"
	@echo "  make init        Terraform 초기화"
	@echo "  make fmt         코드 포맷 정리 (terraform fmt)"
	@echo "  make validate    문법 검증 (terraform validate)"
	@echo "  make plan        변경 미리보기 (적용 안 함)"
	@echo "  make apply       인프라 생성 (확인 프롬프트)"
	@echo "  make apply-auto  인프라 생성 (자동 승인)"
	@echo "  make deploy-db   DB 컨테이너 배포 (apply 이후, proj-mgmt)"
	@echo "  make service     인프라 + DB 한 번에 (apply-auto + deploy-db)"
	@echo "  make output      생성된 IP·ID 출력"
	@echo ""
	@echo "  [ Monitoring ]"
	@echo "  make monitoring-bootstrap   Monitoring Stack 초기 구성"
	@echo "  make monitoring-nginx-logs  AWS Nginx Log Backup(:9105) 설정"
	@echo "  make monitoring-service     Monitoring 전체 구성 (bootstrap + nginx-logs)"
	@echo "  make full-service           인프라 + DB + Monitoring 전체 구성"
	@echo ""
	@echo "  [ 정리 ]"
	@echo "  make destroy-db  Replica DB 스택만 정리 (compose down -v)"
	@echo "  make destroy     Monitoring(AWS+컨테이너) + DB + 인프라 전체 삭제"
	@echo "  make clean       자동 생성 파일 삭제 (state·키 등)"
	@echo ""

# ── 초기 설정 ─────────────────────────────────────────────
setup:
	@chmod +x setup.sh check.sh scripts/deploy-app.sh scripts/set-fail2ban.sh
	./setup.sh

check:
	@chmod +x check.sh
	./check.sh

# ── Terraform ─────────────────────────────────────────────
define TF_WITH_TS
	@TS_STATUS_OUT=$$(tailscale status 2>&1); \
	REPLICA_TS_IP=$$(tailscale ip -4 2>/dev/null | head -1); \
	if [ -z "$$REPLICA_TS_IP" ]; then \
		echo "❌ Tailscale IP를 찾을 수 없습니다. Tailscale을 확인하세요."; \
		exit 1; \
	fi; \
	LOCAL_STATUS=$$(echo "$$TS_STATUS_OUT" | grep "$$REPLICA_TS_IP"); \
	if echo "$$LOCAL_STATUS" | grep -qiE "logged out|offline"; then \
		echo "❌ 로컬 Tailscale 상태가 올바르지 않습니다 (Logged out 또는 Offline)."; \
		exit 1; \
	fi; \
	echo "✅ Detected Replica DB Tailscale IP: $$REPLICA_TS_IP"; \
	export TF_VAR_db_host_replica=$$REPLICA_TS_IP; \
	export TF_VAR_docker_user=$(DOCKER_USER); \
	cd $(TF_DIR) &&
endef

init:
	cd $(TF_DIR) && terraform init -backend-config=hcl/backend.hcl

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate:
	cd $(TF_DIR) && terraform validate

plan:
	$(TF_WITH_TS) terraform plan

apply:
	$(TF_WITH_TS) terraform apply -parallelism=3

apply-auto:
	$(TF_WITH_TS) terraform apply --auto-approve -parallelism=3

# ── Ansible (DB 배포) ─────────────────────────────────────
deploy-db:   ## proj-mgmt에서 DB 컨테이너 배포 (terraform apply 이후)
	@REAL_DB_IP=$$(tailscale status | grep -E "lb-db(-[0-9]+)?" | grep -v "offline" | awk '{print $$1}' | head -n 1); \
	if [ -n "$$REAL_DB_IP" ]; then \
		echo "🔄 Updating database IP in inventory.yml to active Tailscale IP: $$REAL_DB_IP"; \
		sed -i "s/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/$$REAL_DB_IP/g" $(TF_DIR2)/inventory.yml; \
	fi
	cd $(TF_DIR2) && ansible-playbook db-site.yml
	@echo "🔌 Warming up Tailscale tunnel to App instances..."
	@APP_IP=$$(tailscale status | grep -E "lb-app-i-[0-9a-f]+" | grep -v "offline" | awk '{print $$1}'); \
	if [ -n "$$APP_IP" ]; then ping -c 3 $$APP_IP >/dev/null 2>&1 || true; fi


deploy-app:
	@DB_HOST_MAIN=$$(cd $(TF_DIR) && terraform output -raw db_private_ip); \
	DB_HOST_REPLICA=$$(tailscale ip -4 2>/dev/null | head -1); \
	APP_IP=$$(tailscale status | grep -E "lb-app-i-[0-9a-f]+" | grep -v "offline" | awk '{print $$1}' | head -1); \
	if [ -z "$$APP_IP" ]; then echo "❌ App IP 없음"; exit 1; fi; \
	echo "✅ Deploy to $$APP_IP"; \
	scp -o StrictHostKeyChecking=no -i infra/terraform/lb-key.pem -r docker scripts ec2-user@$$APP_IP:/tmp/; \
	ssh -o StrictHostKeyChecking=no -i infra/terraform/lb-key.pem ec2-user@$$APP_IP "sudo mkdir -p /opt/lockbank && sudo rm -rf /opt/lockbank/docker /opt/lockbank/scripts && sudo mv /tmp/docker /opt/lockbank/docker && sudo mv /tmp/scripts /opt/lockbank/scripts && sudo chown -R ec2-user:ec2-user /opt/lockbank"; \
	ssh -i infra/terraform/lb-key.pem ec2-user@$$APP_IP "chmod +x /opt/lockbank/scripts/*.sh"; \
	ssh -i infra/terraform/lb-key.pem ec2-user@$$APP_IP "DOCKER_USER=$(DOCKER_USER) DB_HOST_MAIN=$$DB_HOST_MAIN DB_HOST_REPLICA=$$DB_HOST_REPLICA LOKI_HOST=$$DB_HOST_REPLICA bash /opt/lockbank/scripts/deploy-app.sh"; \
	ssh -i infra/terraform/lb-key.pem ec2-user@$$APP_IP "bash /opt/lockbank/scripts/set-fail2ban.sh"

build-push:
	@if [ -n "$(DOCKER_USER_FALLBACK)" ]; then echo "⚠️  Docker config 파싱 실패 → 기본값 'zeongni'로 push합니다. docker login 후 재실행을 권장합니다."; fi
	@DOCKER_USER=$(DOCKER_USER) ./scripts/build-push-image.sh

build-push-bootstrap:
	@if [ -n "$(DOCKER_USER_FALLBACK)" ]; then echo "⚠️  Docker config 파싱 실패 → 기본값 'zeongni'로 push합니다. docker login 후 재실행을 권장합니다."; fi
	docker build \
	-f docker/bootstrap/Dockerfile \
	-t $(DOCKER_USER)/lock-bootstrap:latest .
	docker push $(DOCKER_USER)/lock-bootstrap:latest

## 인프라 + DB까지 한 번에
service: build-push build-push-bootstrap apply-auto deploy-db

output:
	@echo ""
	@echo "=== 생성된 리소스 출력 ==="
	cd $(TF_DIR) && terraform output
	@echo ""

destroy-db:   ## replica DB 스택(compose) 정리 — down -v (proj-mgmt 로컬)
	cd $(TF_DIR2) && ansible-playbook db-destroy.yml

destroy:
	@echo ""
	@echo "⚠️  Terraform 인프라 및 Monitoring Stack이 삭제됩니다."
	@echo ""
	@echo "🧹 Monitoring AWS 리소스(Lambda/IAM/Alarm/SNS구독) 정리 중..."
	- cd monitoring && $(MAKE) teardown-force
	@echo ""
	@echo "🧹 Monitoring Stack(컨테이너/볼륨) 정리 중..."
	- cd monitoring && $(MAKE) destroy
	@echo ""
	@echo "🧹 Replica DB 스택(컨테이너/볼륨) 정리 중..."
	- $(MAKE) destroy-db
	@echo ""
	@echo "🧨 Terraform 인프라 삭제 중..."
	cd $(TF_DIR) && terraform destroy --auto-approve

# ── Monitoring ───────────────────────────────────────────
monitoring-bootstrap:
	cd monitoring && $(MAKE) bootstrap

monitoring-nginx-logs:
	@echo "🔐 nginx 로그 백업 설정에 sudo 권한이 필요합니다."
	@sudo -v
	sudo bash monitoring/scripts/setup_aws_nginx_log_backup.sh

monitoring-service: monitoring-bootstrap monitoring-nginx-logs

full-service:
	@sudo -v
	$(MAKE) service
	$(MAKE) monitoring-service

# ── 정리 ──────────────────────────────────────────────────
# 주의: .terraform.lock.hcl 은 팀 버전 고정용이라 삭제하지 않습니다(커밋 대상).
clean:
	@echo "자동 생성 파일 삭제 중..."
	rm -f  $(TF_DIR)/*.pem
	rm -f  $(TF_DIR)/*.pem.pub
	rm -rf $(TF_DIR)/.terraform
	rm -f  $(TF_DIR2)/inventory.yml
	rm -f  $(TF_DIR2)/ansible.cfg
	@echo "정리 완료 (.terraform.lock.hcl 은 보존)"
