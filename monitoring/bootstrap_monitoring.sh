#!/bin/bash

set -euo pipefail

echo "============================================="
echo " Lock & Lock Monitoring Bootstrap"
echo "============================================="

if ! command -v aws >/dev/null 2>&1; then
    echo "[ERROR] aws CLI가 설치되어 있지 않습니다."
    exit 1
fi

if [ ! -f ".env" ]; then
    echo "[ERROR] monitoring/.env 파일이 없습니다."
    echo ""
    echo "cp .env.example .env"
    echo "vi .env"
    exit 1
fi

echo "[OK] .env 확인"

required_vars=(
    TS_API_KEY
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_DEFAULT_REGION
)

for var in "${required_vars[@]}"; do
    value="$(grep -E "^${var}=" .env | head -1 | cut -d '=' -f2- || true)"

    if [ -z "$value" ]; then
        echo "[ERROR] .env에 ${var} 값이 없습니다."
        exit 1
    fi
done

echo "[OK] .env 필수값 확인"

APP_IP=$(tailscale status | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')

if [ -z "$APP_IP" ]; then
    echo "[ERROR] App Tailscale IP를 찾을 수 없습니다."
    exit 1
fi

APP_HEALTH_URL="http://${APP_IP}/health"

export AWS_ACCESS_KEY_ID="$(awk -F= '$1=="AWS_ACCESS_KEY_ID"{print substr($0, index($0,$2)); exit}' .env)"
export AWS_SECRET_ACCESS_KEY="$(awk -F= '$1=="AWS_SECRET_ACCESS_KEY"{print substr($0, index($0,$2)); exit}' .env)"
export AWS_DEFAULT_REGION="$(awk -F= '$1=="AWS_DEFAULT_REGION"{print substr($0, index($0,$2)); exit}' .env)"

AWS_ALB_LOAD_BALANCER=$(
    aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[?starts_with(LoadBalancerName, `lb-`)].LoadBalancerArn | [0]' \
        --output text \
    | awk -F'loadbalancer/' '{print $2}'
)

AWS_BLUE_TARGET_GROUP=$(
    aws elbv2 describe-target-groups \
        --query 'TargetGroups[?starts_with(TargetGroupName, `lb-`) && contains(TargetGroupName, `blue`)].TargetGroupArn | [0]' \
        --output text \
    | awk -F'targetgroup/' '{print "targetgroup/" $2}'
)

AWS_GREEN_TARGET_GROUP=$(
    aws elbv2 describe-target-groups \
        --query 'TargetGroups[?starts_with(TargetGroupName, `lb-`) && contains(TargetGroupName, `green`)].TargetGroupArn | [0]' \
        --output text \
    | awk -F'targetgroup/' '{print "targetgroup/" $2}'
)

AWS_BLUE_ASG_NAME=$(
    aws autoscaling describe-auto-scaling-groups \
        --query 'AutoScalingGroups[?starts_with(AutoScalingGroupName, `lb-`) && contains(AutoScalingGroupName, `blue`)].AutoScalingGroupName | [0]' \
        --output text
)

AWS_GREEN_ASG_NAME=$(
    aws autoscaling describe-auto-scaling-groups \
        --query 'AutoScalingGroups[?starts_with(AutoScalingGroupName, `lb-`) && contains(AutoScalingGroupName, `green`)].AutoScalingGroupName | [0]' \
        --output text
)

AWS_APP_PRIVATE_IP=$(
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=lb-app*" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].PrivateIpAddress | [0]" \
        --output text
)

AWS_BASTION_PUBLIC_IP=$(
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=lb-bastion*" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].PublicIpAddress | [0]" \
        --output text
)

generated_vars=(
    AWS_ALB_LOAD_BALANCER
    AWS_BLUE_TARGET_GROUP
    AWS_GREEN_TARGET_GROUP
    AWS_BLUE_ASG_NAME
    AWS_GREEN_ASG_NAME
    AWS_APP_PRIVATE_IP
    AWS_BASTION_PUBLIC_IP
)

for var in "${generated_vars[@]}"; do
    value="${!var}"

    if [ -z "$value" ] || [ "$value" = "None" ]; then
        echo "[ERROR] AWS 리소스 자동 조회 실패: ${var}"
        exit 1
    fi
done

cat > .env.generated <<EOF
APP_HEALTH_URL=${APP_HEALTH_URL}
AWS_ALB_LOAD_BALANCER=${AWS_ALB_LOAD_BALANCER}
AWS_BLUE_TARGET_GROUP=${AWS_BLUE_TARGET_GROUP}
AWS_GREEN_TARGET_GROUP=${AWS_GREEN_TARGET_GROUP}
AWS_BLUE_ASG_NAME=${AWS_BLUE_ASG_NAME}
AWS_GREEN_ASG_NAME=${AWS_GREEN_ASG_NAME}
AWS_APP_PRIVATE_IP=${AWS_APP_PRIVATE_IP}
AWS_BASTION_PUBLIC_IP=${AWS_BASTION_PUBLIC_IP}
AWS_SSH_KEY_PATH=/app/ssh/lb-key.pem
EOF

echo "[OK] Generated .env.generated"
cat .env.generated

docker compose \
    --env-file .env \
    --env-file .env.generated \
    -f docker-compose.monitoring.yaml \
    up -d

echo "[OK] Monitoring Stack Started"

echo ""
echo "============================================="
echo " Auto Discovered Resources"
echo "============================================="

echo "APP_HEALTH_URL      = ${APP_HEALTH_URL}"
echo "APP_PRIVATE_IP      = ${AWS_APP_PRIVATE_IP}"
echo "BASTION_PUBLIC_IP   = ${AWS_BASTION_PUBLIC_IP}"

echo ""
echo "ALB                 = ${AWS_ALB_LOAD_BALANCER}"
echo "BLUE_TG             = ${AWS_BLUE_TARGET_GROUP}"
echo "GREEN_TG            = ${AWS_GREEN_TARGET_GROUP}"

echo ""
echo "BLUE_ASG            = ${AWS_BLUE_ASG_NAME}"
echo "GREEN_ASG           = ${AWS_GREEN_ASG_NAME}"

echo ""
echo "============================================="
echo " Service Discovery"
echo "============================================="

curl -sf http://localhost:9999/app-targets >/dev/null \
    && echo "[OK] app-targets" \
    || echo "[FAIL] app-targets"

curl -sf http://localhost:9999/db-targets >/dev/null \
    && echo "[OK] db-targets" \
    || echo "[FAIL] db-targets"