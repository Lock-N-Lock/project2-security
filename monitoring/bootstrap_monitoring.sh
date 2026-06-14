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

APP_HEALTH_URL="${APP_HEALTH_URL:-http://${APP_IP}/health}"

export AWS_ACCESS_KEY_ID="$(grep -E '^AWS_ACCESS_KEY_ID=' .env | head -1 | cut -d '=' -f2-)"
export AWS_SECRET_ACCESS_KEY="$(grep -E '^AWS_SECRET_ACCESS_KEY=' .env | head -1 | cut -d '=' -f2-)"
export AWS_DEFAULT_REGION="$(grep -E '^AWS_DEFAULT_REGION=' .env | head -1 | cut -d '=' -f2-)"

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

generated_vars=(
    AWS_ALB_LOAD_BALANCER
    AWS_BLUE_TARGET_GROUP
    AWS_GREEN_TARGET_GROUP
    AWS_BLUE_ASG_NAME
    AWS_GREEN_ASG_NAME
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
echo "[INFO] Prometheus Targets"

if command -v jq >/dev/null 2>&1; then
    curl -s http://localhost:9090/api/v1/targets \
    | jq -r '.data.activeTargets[] |
    "[ " + .labels.job + " ] " + .labels.instance + " -> " + .health'
else
    echo "[WARN] jq가 없어 Target 요약 출력은 생략합니다."
    echo "       수동 확인: http://localhost:9090/targets"
fi