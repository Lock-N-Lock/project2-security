#!/bin/bash
# =============================================================
# 파일위치 : ~/project2-security/check.sh
# 환경·자격증명 상태 확인 (Lock & Lock)
# 실행 : bash check.sh  또는  make check
# =============================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }

echo ""
echo "============================================="
echo "  Lock & Lock 환경 상태 확인"
echo "============================================="
echo ""

# ── 1. 필수 도구 ───────────────────────────────────────────
echo "[ 1 ] 필수 도구 설치 확인"
command -v aws       &>/dev/null && ok "AWS CLI : $(aws --version 2>&1 | awk '{print $1}')"  || fail "AWS CLI 미설치 → bash setup.sh"
command -v terraform &>/dev/null && ok "Terraform : $(terraform -version | head -1)"          || fail "Terraform 미설치 → bash setup.sh"
command -v ansible   &>/dev/null && ok "Ansible : $(ansible --version | head -1)"             || fail "Ansible 미설치 → bash setup.sh"
command -v docker    &>/dev/null && ok "Docker : $(docker --version)"                         || fail "Docker 미설치 → bash setup.sh"
echo ""

# ── 2. Docker 데몬·권한·로그인 ─────────────────────────────
echo "[ 2 ] Docker 상태 확인"
if command -v docker &>/dev/null; then
    if systemctl is-active --quiet docker 2>/dev/null; then
        ok "docker 데몬 실행 중"
    else
        fail "docker 데몬 미실행 → sudo systemctl start docker"
    fi
    if docker info &>/dev/null; then
        ok "현재 사용자로 docker 사용 가능"
    else
        warn "docker 권한 없음 → newgrp docker 또는 재로그인 필요"
    fi
    if docker info 2>/dev/null | grep -q "Username:"; then
        ok "Docker Hub 로그인됨: $(docker info 2>/dev/null | grep Username | awk '{print $2}')"
    else
        warn "Docker Hub 미로그인 → docker login (C 트랙 push용)"
    fi
fi
echo ""

# ── 3. AWS 자격증명 ────────────────────────────────────────
echo "[ 3 ] AWS 자격증명 확인"
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    ok "자격증명 유효 (계정 $ACCOUNT)"
    [ "$REGION" = "ap-northeast-2" ] && ok "리전 정상 : ap-northeast-2" || warn "리전이 ap-northeast-2(서울)이 아님: $REGION"
else
    fail "자격증명 없음/만료 → aws configure"
fi
echo ""

# ── 4. 프로젝트 폴더 ───────────────────────────────────────
echo "[ 4 ] 프로젝트 폴더 확인"
[ -d "$HOME/project2-security/infra/terraform" ] && ok "infra/terraform 존재" || fail "infra/terraform 없음 → scaffold 확인"
echo ""

# ── 5. 비용 안내 ───────────────────────────────────────────
echo "[ 5 ] 비용 안내"
echo "  - 실습 후 반드시 make destroy 로 비용 절감"
echo ""

echo "============================================="
echo "  확인 완료"
echo "============================================="
echo ""