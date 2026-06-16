#!/bin/bash

set -euo pipefail

echo "============================================="
echo " Lock & Lock Monitoring Bootstrap"
echo "============================================="

prompt_if_empty() {
    local key="$1"
    local default="${2:-}"
    local secret="${3:-false}"

    local value
    value="$(grep -E "^${key}=" .env | head -1 | cut -d '=' -f2- || true)"

    if [ -z "$value" ]; then
        if [ "$secret" = "true" ]; then
            read -r -s -p "${key}: " value
            echo ""
        elif [ -n "$default" ]; then
            read -r -p "${key} [${default}]: " value
            value="${value:-$default}"
        else
            read -r -p "${key}: " value
        fi

        sed -i "s|^${key}=.*|${key}=${value}|" .env
    fi
}

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

echo "[OK] .env 파일 확인 완료"

install_zip_on_rocky() {
    if command -v zip >/dev/null 2>&1; then
        return 0
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        echo "[ERROR] /etc/os-release 파일을 찾을 수 없습니다. zip 설치 여부를 확인할 수 없습니다."
        exit 1
    fi

    if [[ "${ID:-}" != "rocky" && "${ID_LIKE:-}" != *"rhel"* ]]; then
        echo "[ERROR] zip 명령어가 없고, 현재 OS가 Rocky/RHEL 계열이 아닙니다. zip을 수동 설치해주세요."
        exit 1
    fi

    echo "[INFO] zip 패키지 설치 진행"

    if command -v sudo >/dev/null 2>&1; then
        sudo dnf install -y zip
    else
        dnf install -y zip
    fi
}

install_zip_on_rocky

required_commands=(
    aws
    docker
    tailscale
    zip
)

for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] ${cmd} 명령어를 찾을 수 없습니다."
        exit 1
    fi
done

echo "[OK] 필수 명령어 확인 완료"

prompt_if_empty "TS_API_KEY" "" true
prompt_if_empty "TELEGRAM_BOT_TOKEN" "" true
prompt_if_empty "TELEGRAM_CHAT_ID" "" true
prompt_if_empty "AWS_ACCESS_KEY_ID" "" true
prompt_if_empty "AWS_SECRET_ACCESS_KEY" "" true
prompt_if_empty "AWS_DEFAULT_REGION" "ap-northeast-2"

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

echo "[OK] .env 필수값 확인 완료"

APP_IP=$(tailscale status | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')

if [ -z "$APP_IP" ]; then
    echo "[ERROR] App Tailscale IP를 찾을 수 없습니다."
    exit 1
fi

APP_HEALTH_URL="http://${APP_IP}/health"

export AWS_ACCESS_KEY_ID="$(awk -F= '$1=="AWS_ACCESS_KEY_ID"{print substr($0, index($0,$2)); exit}' .env)"
export AWS_SECRET_ACCESS_KEY="$(awk -F= '$1=="AWS_SECRET_ACCESS_KEY"{print substr($0, index($0,$2)); exit}' .env)"
export AWS_DEFAULT_REGION="$(awk -F= '$1=="AWS_DEFAULT_REGION"{print substr($0, index($0,$2)); exit}' .env)"
SNS_TOPIC_NAME="$(awk -F= '$1=="SNS_TOPIC_NAME"{print substr($0, index($0,$2)); exit}' .env)"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-lb-alerts}"
export SNS_TOPIC_NAME

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

echo "[OK] .env.generated 생성 완료"
cat .env.generated

if [ -x "./lambda/cloudwatch-telegram-notifier/deploy_cloudwatch_telegram_lambda.sh" ]; then
    echo "[INFO] CloudWatch Telegram Notifier 배포 시작"
    ./lambda/cloudwatch-telegram-notifier/deploy_cloudwatch_telegram_lambda.sh
    echo "[OK] CloudWatch Telegram Notifier 배포 완료"
else
    echo "[ERROR] CloudWatch Telegram Notifier 배포 스크립트를 찾을 수 없거나 실행 권한이 없습니다."
    exit 1
fi

docker compose \
    --env-file .env \
    --env-file .env.generated \
    -f docker-compose.monitoring.yaml \
    up -d

LAMBDA_FUNCTION_NAME="lb-cloudwatch-telegram-notifier"

LAMBDA_ARN=$(
    aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null || true
)

SNS_TOPIC_ARN=$(
    aws sns list-topics \
        --query "Topics[?ends_with(TopicArn, ':${SNS_TOPIC_NAME}')].TopicArn | [0]" \
        --output text 2>/dev/null || true
)

if [ -z "$SNS_TOPIC_ARN" ] || [ "$SNS_TOPIC_ARN" = "None" ]; then
    echo "[ERROR] SNS Topic 자동 조회 실패: ${SNS_TOPIC_NAME}"
    exit 1
fi

if [ -z "$LAMBDA_ARN" ] || [ "$LAMBDA_ARN" = "None" ]; then
    echo "[ERROR] Lambda 자동 조회 실패: ${LAMBDA_FUNCTION_NAME}"
    exit 1
fi

echo "[OK] Monitoring Stack 시작 완료"

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
echo "SNS_TOPIC           = ${SNS_TOPIC_NAME}"
echo "SNS_TOPIC_ARN       = ${SNS_TOPIC_ARN}"
echo "LAMBDA_FUNCTION     = ${LAMBDA_FUNCTION_NAME}"
echo "LAMBDA_ARN          = ${LAMBDA_ARN}"

echo ""
echo "============================================="
echo " Service Discovery"
echo "============================================="

check_sd_endpoint() {
    local name="$1"
    local path="$2"

    if docker exec -i monitoring-tailscale-sd-1 python -c "
import urllib.request
data = urllib.request.urlopen('http://127.0.0.1:9999${path}', timeout=3).read().decode().strip()
raise SystemExit(0 if data and data != '[]' else 1)
" >/dev/null 2>&1
    then
        echo "[OK] ${name}"
    else
        echo "[FAIL] ${name}"
    fi
}

check_sd_endpoint "app-targets" "/app-targets"
check_sd_endpoint "db-targets" "/db-targets"