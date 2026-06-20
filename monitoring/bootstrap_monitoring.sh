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

if ! command -v envsubst >/dev/null 2>&1; then
    echo "[INFO] envsubst(gettext) 설치 진행"

    if command -v sudo >/dev/null 2>&1; then
        sudo dnf install -y gettext
    else
        dnf install -y gettext
    fi
fi

required_commands=(
    aws
    docker
    tailscale
    zip
    envsubst
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

TAILSCALE_STATUS=$(tailscale status)
APP_IP=$(printf '%s\n' "$TAILSCALE_STATUS" | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')

if [ -z "$APP_IP" ]; then
    echo "[ERROR] App Tailscale IP를 찾을 수 없습니다."
    exit 1
fi

APP_HEALTH_URL="http://${APP_IP}/health"

TAILSCALE_IPS=$(tailscale ip -4)
MONITORING_METRICS_HOST=$(printf '%s\n' "$TAILSCALE_IPS" | awk 'NF {print $1; exit}')

if [ -z "$MONITORING_METRICS_HOST" ]; then
    echo "[ERROR] Monitoring Tailscale IP를 찾을 수 없습니다."
    exit 1
fi

NGINX_LOG_METRICS_URL="http://${MONITORING_METRICS_HOST}:9105/nginx_log_metrics.prom"

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

DB_HOST_MAIN=$(
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=lb-db*" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].PrivateIpAddress | [0]" \
        --output text
)

DB_HOST_REPLICA="${MONITORING_METRICS_HOST}"
DB_PORT="${DB_PORT:-5432}"
DB_REPLICA_CONTAINER="${DB_REPLICA_CONTAINER:-lb-postgres-replica}"
NGINX_CONTAINER="${NGINX_CONTAINER:-lb-security-nginx}"
APP_CONTAINER="${APP_CONTAINER:-lb-fastapi}"
GRAFANA_BASE_PATH="/grafana"
GRAFANA_DASHBOARD_UID="dfodmd3s8ecqoc"
GRAFANA_DASHBOARD_SLUG="lockbank-security-and-operations-dashboard"
GRAFANA_ORG_ID="1"
GRAFANA_TIME_FROM="now-24h"
GRAFANA_TIME_TO="now"
GRAFANA_THEME="light"

generated_vars=(
    AWS_ALB_LOAD_BALANCER
    AWS_BLUE_TARGET_GROUP
    AWS_GREEN_TARGET_GROUP
    AWS_BLUE_ASG_NAME
    AWS_GREEN_ASG_NAME
    AWS_APP_PRIVATE_IP
    AWS_BASTION_PUBLIC_IP
    MONITORING_METRICS_HOST
    NGINX_LOG_METRICS_URL
    DB_HOST_MAIN
    DB_HOST_REPLICA
    DB_PORT
    DB_REPLICA_CONTAINER
    NGINX_CONTAINER
    APP_CONTAINER
    GRAFANA_BASE_PATH
    GRAFANA_DASHBOARD_UID
    GRAFANA_DASHBOARD_SLUG
    GRAFANA_ORG_ID
    GRAFANA_TIME_FROM
    GRAFANA_TIME_TO
    GRAFANA_THEME
)

for var in "${generated_vars[@]}"; do
    value="${!var}"

    if [ -z "$value" ] || [ "$value" = "None" ]; then
        echo "[ERROR] 자동 생성 변수 조회 실패: ${var}"
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
MONITORING_METRICS_HOST=${MONITORING_METRICS_HOST}
NGINX_LOG_METRICS_URL=${NGINX_LOG_METRICS_URL}
DB_HOST_MAIN=${DB_HOST_MAIN}
DB_HOST_REPLICA=${DB_HOST_REPLICA}
DB_PORT=${DB_PORT}
DB_REPLICA_CONTAINER=${DB_REPLICA_CONTAINER}
NGINX_CONTAINER=${NGINX_CONTAINER}
APP_CONTAINER=${APP_CONTAINER}
GRAFANA_BASE_PATH=${GRAFANA_BASE_PATH}
GRAFANA_DASHBOARD_UID=${GRAFANA_DASHBOARD_UID}
GRAFANA_DASHBOARD_SLUG=${GRAFANA_DASHBOARD_SLUG}
GRAFANA_ORG_ID=${GRAFANA_ORG_ID}
GRAFANA_TIME_FROM=${GRAFANA_TIME_FROM}
GRAFANA_TIME_TO=${GRAFANA_TIME_TO}
GRAFANA_THEME=${GRAFANA_THEME}
EOF

export APP_HEALTH_URL
export MONITORING_METRICS_HOST

export AWS_ALB_LOAD_BALANCER
export AWS_BLUE_TARGET_GROUP
export AWS_BLUE_ASG_NAME

export GRAFANA_BASE_PATH
export GRAFANA_DASHBOARD_UID
export GRAFANA_DASHBOARD_SLUG
export GRAFANA_ORG_ID
export GRAFANA_TIME_FROM
export GRAFANA_TIME_TO
export GRAFANA_THEME

python3 - <<'PY'
from pathlib import Path
import os
import sys

path = Path("prometheus/prometheus.yaml")

start = "  # BEGIN AUTO GENERATED: nginx-log-metrics"
end = "  # END AUTO GENERATED: nginx-log-metrics"

text = path.read_text()

if start not in text or end not in text:
    print("[ERROR] prometheus.yaml에 nginx-log-metrics 자동 생성 마커가 없습니다.")
    print("[ERROR] 아래 두 줄을 scrape_configs 하단에 추가해야 합니다.")
    print(start)
    print(end)
    sys.exit(1)

block = f'''{start}
  - job_name: nginx-log-metrics
    metrics_path: /nginx_log_metrics.prom
    static_configs:
      - targets:
          - {os.environ["MONITORING_METRICS_HOST"]}:9105
{end}'''

before, rest = text.split(start, 1)
_, after = rest.split(end, 1)

path.write_text(before + block + after)
PY

python3 - <<'PY'
from pathlib import Path
from urllib.parse import urlparse
import os
import sys

path = Path("prometheus/prometheus.yaml")

start = "  # BEGIN AUTO GENERATED: lockbank-app-metrics"
end = "  # END AUTO GENERATED: lockbank-app-metrics"

app_health_url = os.environ.get("APP_HEALTH_URL", "").strip()
if not app_health_url:
    print("[ERROR] APP_HEALTH_URL이 비어 있습니다.")
    sys.exit(1)

parsed = urlparse(app_health_url)
scheme = parsed.scheme or "http"
target = parsed.netloc

if not target:
    print(f"[ERROR] APP_HEALTH_URL에서 target을 추출하지 못했습니다: {app_health_url}")
    sys.exit(1)

text = path.read_text()

if start not in text or end not in text:
    print("[ERROR] prometheus.yaml에 lockbank-app-metrics 자동 생성 마커가 없습니다.")
    print("[ERROR] 아래 두 줄을 scrape_configs 하단에 추가해야 합니다.")
    print(start)
    print(end)
    sys.exit(1)

block = f'''{start}
  - job_name: lockbank-app-metrics
    scheme: {scheme}
    metrics_path: /metrics
    static_configs:
      - targets:
          - {target}
{end}'''

before, rest = text.split(start, 1)
_, after = rest.split(end, 1)

path.write_text(before + block + after)
PY

echo "[OK] prometheus.yaml auto generated scrape jobs 갱신 완료"

envsubst '${GRAFANA_BASE_PATH} ${GRAFANA_DASHBOARD_UID} ${GRAFANA_DASHBOARD_SLUG} ${GRAFANA_ORG_ID} ${GRAFANA_TIME_FROM} ${GRAFANA_TIME_TO} ${GRAFANA_THEME}' \
    < security-center/index.html.template \
    > security-center/index.html

envsubst '${AWS_ALB_LOAD_BALANCER} ${AWS_BLUE_TARGET_GROUP} ${AWS_BLUE_ASG_NAME}' \
    < grafana/dashboards/lockbank-security-operations-dashboard.json.template \
    > grafana/dashboards/lockbank-security-operations-dashboard.json

echo "[OK] Security Center / Grafana Dashboard template 치환 완료"

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

RESET_GRAFANA="${RESET_GRAFANA:-false}"

if [ "$RESET_GRAFANA" = "true" ]; then
    echo "[WARN] Grafana volume 초기화 진행"

    docker compose \
        --env-file .env \
        --env-file .env.generated \
        -f docker-compose.monitoring.yaml \
        stop grafana || true

    docker compose \
        --env-file .env \
        --env-file .env.generated \
        -f docker-compose.monitoring.yaml \
        rm -f grafana || true

    docker volume rm monitoring_grafana_data >/dev/null 2>&1 || true
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
echo "GRAFANA_BASE_PATH   = ${GRAFANA_BASE_PATH}"
echo "GRAFANA_UID         = ${GRAFANA_DASHBOARD_UID}"
echo "GRAFANA_SLUG        = ${GRAFANA_DASHBOARD_SLUG}"
echo "GRAFANA_ORG_ID      = ${GRAFANA_ORG_ID}"
echo "GRAFANA_TIME_FROM   = ${GRAFANA_TIME_FROM}"
echo "GRAFANA_TIME_TO     = ${GRAFANA_TIME_TO}"
echo "GRAFANA_THEME       = ${GRAFANA_THEME}"

echo ""
echo "SNS_TOPIC           = ${SNS_TOPIC_NAME}"
echo "SNS_TOPIC_ARN       = ${SNS_TOPIC_ARN}"
echo "LAMBDA_FUNCTION     = ${LAMBDA_FUNCTION_NAME}"
echo "LAMBDA_ARN          = ${LAMBDA_ARN}"

echo "MONITORING_METRICS_HOST = ${MONITORING_METRICS_HOST}"
echo "NGINX_LOG_METRICS_URL   = ${NGINX_LOG_METRICS_URL}"

echo ""
echo "DB_MAIN            = ${DB_HOST_MAIN}"
echo "DB_REPLICA         = ${DB_HOST_REPLICA}"
echo "DB_PORT            = ${DB_PORT}"
echo "DB_REPLICA_CONTAINER = ${DB_REPLICA_CONTAINER}"
echo "APP_CONTAINER      = ${APP_CONTAINER}"
echo "NGINX_CONTAINER    = ${NGINX_CONTAINER}"

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