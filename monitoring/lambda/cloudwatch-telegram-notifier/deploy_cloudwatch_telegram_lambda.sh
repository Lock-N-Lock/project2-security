#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${MONITORING_DIR}/.env"

FUNCTION_NAME="lb-cloudwatch-telegram-notifier"
ROLE_NAME="lb-cloudwatch-telegram-lambda-role"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] ${ENV_FILE} 파일이 없습니다."
  exit 1
fi

prompt_env_if_empty() {
  local key="$1"
  local default="${2:-}"
  local secret="${3:-false}"

  local value
  value="$(grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d '=' -f2- || true)"

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

    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
    export "${key}=${value}"
  fi
}

prompt_env_if_empty "TELEGRAM_BOT_TOKEN" "" true
prompt_env_if_empty "TELEGRAM_CHAT_ID" "" true

set -a
source "${ENV_FILE}"
set +a

TOPIC_NAME="${SNS_TOPIC_NAME:-lb-alerts}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

echo "[INFO] Packaging Lambda..."
cd "${SCRIPT_DIR}"
rm -f lambda.zip
zip -q lambda.zip lambda_function.py

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "[OK] IAM role already exists: ${ROLE_NAME}"
else
  echo "[INFO] Creating IAM role: ${ROLE_NAME}"

  cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file://trust-policy.json >/dev/null

  aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  echo "[INFO] Waiting for IAM role propagation..."
  sleep 10
fi

ROLE_ARN="$(aws iam get-role \
  --role-name "${ROLE_NAME}" \
  --query 'Role.Arn' \
  --output text)"

TOPIC_ARN="$(aws sns list-topics \
  --region "${REGION}" \
  --query "Topics[?ends_with(TopicArn, ':${TOPIC_NAME}')].TopicArn | [0]" \
  --output text)"

if [ "${TOPIC_ARN}" = "None" ] || [ -z "${TOPIC_ARN}" ]; then
  echo "[ERROR] SNS Topic not found: ${TOPIC_NAME}"
  exit 1
fi

echo "[OK] SNS Topic ARN: ${TOPIC_ARN}"

if aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "[INFO] Updating Lambda code..."
  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file fileb://lambda.zip \
    --region "${REGION}" >/dev/null

  echo "[INFO] Waiting for Lambda code update..."
  aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"
  
  echo "[INFO] Updating Lambda environment variables..."
  aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --environment "Variables={TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN},TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}}" \
    --region "${REGION}" >/dev/null
  echo "[INFO] Waiting for Lambda configuration update..."
  aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"
else
  echo "[INFO] Creating Lambda function..."
  aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime python3.12 \
    --role "${ROLE_ARN}" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda.zip \
    --environment "Variables={TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN},TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}}" \
    --region "${REGION}" >/dev/null

  echo "[INFO] Waiting for Lambda creation..."
  aws lambda wait function-active \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"
fi

echo "[INFO] Allowing SNS to invoke Lambda..."
aws lambda add-permission \
  --function-name "${FUNCTION_NAME}" \
  --statement-id "AllowExecutionFromSNS-${TOPIC_NAME}" \
  --action "lambda:InvokeFunction" \
  --principal sns.amazonaws.com \
  --source-arn "${TOPIC_ARN}" \
  --region "${REGION}" >/dev/null 2>&1 || true

LAMBDA_ARN="$(aws lambda get-function \
  --function-name "${FUNCTION_NAME}" \
  --region "${REGION}" \
  --query 'Configuration.FunctionArn' \
  --output text)"

echo "[INFO] Checking SNS subscription..."
SUB_EXISTS="$(aws sns list-subscriptions-by-topic \
  --topic-arn "${TOPIC_ARN}" \
  --region "${REGION}" \
  --query "Subscriptions[?Endpoint=='${LAMBDA_ARN}'].SubscriptionArn | [0]" \
  --output text)"

if [ "${SUB_EXISTS}" = "None" ] || [ -z "${SUB_EXISTS}" ]; then
  echo "[INFO] Subscribing Lambda to SNS Topic..."
  aws sns subscribe \
    --topic-arn "${TOPIC_ARN}" \
    --protocol lambda \
    --notification-endpoint "${LAMBDA_ARN}" \
    --region "${REGION}" >/dev/null
else
  echo "[OK] SNS subscription already exists."
fi

echo "[OK] CloudWatch Alarm -> SNS -> Lambda -> Telegram deployment completed."
echo "[INFO] Function: ${FUNCTION_NAME}"
echo "[INFO] SNS Topic: ${TOPIC_ARN}"
