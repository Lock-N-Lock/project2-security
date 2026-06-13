#!/bin/bash

set -euo pipefail

echo "============================================="
echo " Lock & Lock Monitoring Bootstrap"
echo "============================================="

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
    AWS_ALB_NAME
    AWS_BLUE_TARGET_GROUP_NAME
    AWS_GREEN_TARGET_GROUP_NAME
    AWS_BLUE_ASG_NAME
    AWS_GREEN_ASG_NAME
)

for var in "${required_vars[@]}"; do
    value="$(grep -E "^${var}=" .env | cut -d '=' -f2- || true)"

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

APP_HEALTH_URL="http://${APP_IP}:8080/health"

cat > .env.generated <<EOF
APP_HEALTH_URL=${APP_HEALTH_URL}
EOF

echo "[OK] APP_HEALTH_URL=${APP_HEALTH_URL}"

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