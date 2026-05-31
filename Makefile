# =============================================================
# 파일위치 : ~/project2-security/Makefile
# Lock & Lock 팀 프로젝트 Makefile
# 사용법: 레포 루트(~/project2-security)에서  make [명령어]
# =============================================================

TF_DIR := infra/terraform

.PHONY: help setup check init fmt validate plan apply apply-auto output destroy clean

# 기본 실행 (make)
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
	@echo "  make apply  	  인프라 생성 (확인 프롬프트)"
	@echo "  make apply-auto  인프라 생성 (자동 승인)"
	@echo "  make output      생성된 IP·ID 출력"
	@echo "  make destroy     인프라 전체 삭제 (자동 승인)"
	@echo ""
	@echo "  [ 정리 ]"
	@echo "  make clean       자동 생성 파일 삭제 (state·키 등)"
	@echo ""

# ── 초기 설정 ─────────────────────────────────────────────
setup:
	@chmod +x setup.sh check.sh
	./setup.sh

check:
	@chmod +x check.sh
	./check.sh

# ── Terraform ─────────────────────────────────────────────
init:
	cd $(TF_DIR) && terraform init

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate:
	cd $(TF_DIR) && terraform validate

plan:
	cd $(TF_DIR) && terraform plan

apply:
	cd $(TF_DIR) && terraform apply -parallelism=3

apply-auto:
	cd $(TF_DIR) && terraform apply --auto-approve -parallelism=3

output:
	@echo ""
	@echo "=== 생성된 리소스 출력 ==="
	cd $(TF_DIR) && terraform output
	@echo ""

destroy:
	@echo ""
	@echo "⚠️  모든 인프라가 삭제됩니다. 실습 후 비용 절감용."
	@echo ""
	cd $(TF_DIR) && terraform destroy --auto-approve

# ── 정리 ──────────────────────────────────────────────────
# 주의: .terraform.lock.hcl 은 팀 버전 고정용이라 삭제하지 않습니다(커밋 대상).
clean:
	@echo "자동 생성 파일 삭제 중..."
	rm -f  $(TF_DIR)/*.pem
	rm -f  $(TF_DIR)/inventory.yml
	rm -f  $(TF_DIR)/ansible.cfg
	rm -f  $(TF_DIR)/terraform.tfstate
	rm -f  $(TF_DIR)/terraform.tfstate.backup
	rm -rf $(TF_DIR)/.terraform
	@echo "정리 완료 (.terraform.lock.hcl 은 보존)"