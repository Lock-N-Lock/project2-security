#!/bin/bash
# =============================================================
# 파일위치 : ~/project2-security/setup.sh
# 팀 프로젝트 환경 설정 스크립트 (Lock & Lock)
# 대상 OS : Rocky Linux 8.x
# 목적    : AWS CLI v2 + Terraform + Ansible + Docker 설치·검증
# 실행    : bash setup.sh
# =============================================================

set -e  # 오류 발생 시 즉시 중단

# OS 호환성 체크
if [ ! -f /etc/redhat-release ] && [ ! -f /etc/rocky-release ]; then
    echo "❌ 이 스크립트는 Rocky Linux 8 기반 환경만 지원합니다."
    echo "    다른 OS 환경에서는 아래 도구들을 수동으로 설치해 주세요:"
    echo "    - AWS CLI v2 / Terraform / Ansible / Docker"
    exit 1
fi

# ── 색상 출력 함수 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

echo ""
echo "============================================="
echo "  Lock & Lock 환경 설정 시작"
echo "  Rocky 8 | AWS CLI · Terraform · Ansible · Docker"
echo "============================================="
echo ""

# ── STEP 1 : 기존 설치 확인 ────────────────────────────────
info "STEP 1/6 : 기존 설치 여부 확인 중..."
AWS_INSTALLED=false; TF_INSTALLED=false; ANSIBLE_INSTALLED=false; DOCKER_INSTALLED=false
command -v aws       &>/dev/null && { warning "AWS CLI 이미 설치됨 → 건너뜀";   AWS_INSTALLED=true; }
command -v terraform &>/dev/null && { warning "Terraform 이미 설치됨 → 건너뜀"; TF_INSTALLED=true; }
command -v ansible   &>/dev/null && { warning "Ansible 이미 설치됨 → 건너뜀";   ANSIBLE_INSTALLED=true; }
command -v docker    &>/dev/null && { warning "Docker 이미 설치됨 → 건너뜀";    DOCKER_INSTALLED=true; }

# ── STEP 1.5 : make 설치 ───────────────────────────────────
info "STEP 1.5/6 : make 확인 중..."
if ! command -v make &>/dev/null; then
    sudo dnf install -y make -q || error "make 설치 실패"
    success "make 설치 완료"
else
    info "  make 이미 설치됨"
fi

# ── STEP 2 : AWS CLI v2 ────────────────────────────────────
if [ "$AWS_INSTALLED" = false ]; then
    info "STEP 2/6 : AWS CLI v2 설치 중..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    cd "$TMP_DIR"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" || error "AWS CLI 다운로드 실패"
    sudo dnf install -y unzip -q
    unzip -q awscliv2.zip
    sudo ./aws/install
    cd ~
    rm -rf "$TMP_DIR"
    trap - EXIT
    command -v aws &>/dev/null && success "AWS CLI 설치 완료: $(aws --version 2>&1 | awk '{print $1}')" || error "AWS CLI 설치 실패"
else
    info "STEP 2/6 : AWS CLI 건너뜀"
fi

# ── STEP 3 : Terraform ─────────────────────────────────────
if [ "$TF_INSTALLED" = false ]; then
    info "STEP 3/6 : Terraform 설치 중..."
    sudo dnf install -y yum-utils -q
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo -q || true
    sudo dnf install -y terraform -q
    command -v terraform &>/dev/null && { success "Terraform 설치 완료: $(terraform -version | head -1)"; terraform -install-autocomplete 2>/dev/null || true; } || error "Terraform 설치 실패"
else
    info "STEP 3/6 : Terraform 건너뜀"
fi

# ── STEP 4 : Ansible ───────────────────────────────────────
if [ "$ANSIBLE_INSTALLED" = false ]; then
    info "STEP 4/6 : Ansible 설치 중..."
    sudo dnf install -y epel-release -q
    sudo dnf install -y ansible -q
    command -v ansible &>/dev/null && success "Ansible 설치 완료: $(ansible --version | head -1)" || error "Ansible 설치 실패"
else
    info "STEP 4/6 : Ansible 건너뜀"
fi

# ── STEP 5 : Docker (project2 신규) ────────────────────────
if [ "$DOCKER_INSTALLED" = false ]; then
    info "STEP 5/6 : Docker 설치 중..."
    sudo dnf remove -y podman buildah runc 2>/dev/null || true   # ← #4: Rocky8 충돌 방지 (한 줄 추가)
    sudo dnf install -y yum-utils -q
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo -q 2>/dev/null || true
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -q || error "Docker 설치 실패"
    sudo systemctl enable --now docker
    # 현재 사용자를 docker 그룹에 추가 (sudo 없이 docker 사용)
    sudo usermod -aG docker "${SUDO_USER:-$USER}"                # ← #5: root 오등록 방지
    command -v docker &>/dev/null && success "Docker 설치 완료: $(docker --version)" || error "Docker 설치 실패"
    warning "docker 그룹 적용을 위해 재로그인 또는 'newgrp docker' 필요"
else
    info "STEP 5/6 : Docker 건너뜀"
fi

# ── STEP 6 : 최종 검증 ─────────────────────────────────────
info "STEP 6/6 : 설치 결과 최종 검증"
echo ""
echo "  ┌─────────────────────────────────────────┐"
command -v aws       &>/dev/null && echo "  │ ✅ AWS CLI   : $(aws --version 2>&1 | awk '{print $1}')" || echo "  │ ❌ AWS CLI   : 실패"
command -v terraform &>/dev/null && echo "  │ ✅ Terraform : $(terraform -version | head -1)"        || echo "  │ ❌ Terraform : 실패"
command -v ansible   &>/dev/null && echo "  │ ✅ Ansible   : $(ansible --version | head -1)"         || echo "  │ ❌ Ansible   : 실패"
command -v docker    &>/dev/null && echo "  │ ✅ Docker    : $(docker --version)"                    || echo "  │ ❌ Docker    : 실패"
echo "  └─────────────────────────────────────────┘"
echo ""

echo "============================================="
success "환경 설치 완료!"
echo "============================================="
echo ""
echo "  다음 단계:"
echo "   1) docker 그룹 적용:  newgrp docker  (또는 재로그인)"
echo "   2) AWS 자격증명 등록:  aws configure"
echo "        region = ap-northeast-2,  output = json"
echo "   3) Docker Hub 로그인:  docker login   (C 트랙 push용)"
echo "   4) 환경 점검:          make check"
echo ""