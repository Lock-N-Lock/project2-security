#!/bin/bash
# =============================================================
# deploy_cloudwatch_telegram_lambda.sh 의 짝(teardown).
# deploy 가 Terraform 밖에서 만든 AWS 리소스만 되돌린다.
#   - CloudWatch 알람  : ${AWS_BLUE_ASG_NAME}-scaleout-detected
#   - SNS 구독         : Lambda endpoint (topic 자체는 Terraform 소관 → 보존)
#   - Lambda 함수      : lb-cloudwatch-telegram-notifier
#   - IAM role         : lb-cloudwatch-telegram-lambda-role (+ 연결 정책)
#
# 기본은 DRY-RUN(삭제 대상만 표시). 실제 삭제는 --force 필요.
#   사용: bash teardown_cloudwatch_telegram_lambda.sh [--force]
# =============================================================
set -uo pipefail   # -e 제외: 개별 삭제 실패해도 끝까지 진행

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${MONITORING_DIR}/.env"
GENERATED_ENV_FILE="${MONITORING_DIR}/.env.generated"

FUNCTION_NAME="lb-cloudwatch-telegram-notifier"
ROLE_NAME="lb-cloudwatch-telegram-lambda-role"

# ── 인자 파싱 (기본 dry-run) ──────────────────────────────
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force|--apply|--yes) FORCE=1 ;;
    --dry-run)             FORCE=0 ;;
    *) echo "[WARN] 알 수 없는 인자 무시: $arg" ;;
  esac
done

# ── env 로드 (있으면) ─────────────────────────────────────
set -a
[ -f "${ENV_FILE}" ] && source "${ENV_FILE}"
[ -f "${GENERATED_ENV_FILE}" ] && source "${GENERATED_ENV_FILE}"
set +a

REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
TOPIC_NAME="${SNS_TOPIC_NAME:-lb-alerts}"

if [ "${FORCE}" -eq 1 ]; then
  echo "🧨 [TEARDOWN] 실제 삭제 모드 (--force)"
else
  echo "🔍 [DRY-RUN] 삭제 대상만 표시합니다. 실제 삭제는 --force 를 붙이세요."
fi
echo "    REGION=${REGION}  TOPIC=${TOPIC_NAME}  ASG=${AWS_BLUE_ASG_NAME:-<unset>}"
echo ""

# run "<설명>" <command...>  : force 면 실행, 아니면 표시만
run() {
  local desc="$1"; shift
  if [ "${FORCE}" -eq 1 ]; then
    echo "  → ${desc}"
    "$@" || echo "    [WARN] 실패(무시): ${desc}"
  else
    echo "  [would] ${desc}"
  fi
}

# ── 1) CloudWatch 알람 ────────────────────────────────────
if [ -n "${AWS_BLUE_ASG_NAME:-}" ]; then
  ALARM_NAME="${AWS_BLUE_ASG_NAME}-scaleout-detected"
  FOUND="$(aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" --region "${REGION}" \
    --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null || true)"
  if [ -n "${FOUND}" ] && [ "${FOUND}" != "None" ]; then
    run "CloudWatch 알람 삭제: ${ALARM_NAME}" \
      aws cloudwatch delete-alarms --alarm-names "${ALARM_NAME}" --region "${REGION}"
  else
    echo "  [skip] CloudWatch 알람 없음: ${ALARM_NAME}"
  fi
else
  echo "  [skip] AWS_BLUE_ASG_NAME 미설정 → 알람 식별 불가"
fi

# ── 2) SNS 구독 해제 (topic 자체는 Terraform 소관 → 보존) ──
LAMBDA_ARN="$(aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${REGION}" \
  --query 'Configuration.FunctionArn' --output text 2>/dev/null || true)"
TOPIC_ARN="$(aws sns list-topics --region "${REGION}" \
  --query "Topics[?ends_with(TopicArn, ':${TOPIC_NAME}')].TopicArn | [0]" --output text 2>/dev/null || true)"

if [ -n "${TOPIC_ARN}" ] && [ "${TOPIC_ARN}" != "None" ] && \
   [ -n "${LAMBDA_ARN}" ] && [ "${LAMBDA_ARN}" != "None" ]; then
  SUB_ARN="$(aws sns list-subscriptions-by-topic --topic-arn "${TOPIC_ARN}" --region "${REGION}" \
    --query "Subscriptions[?Endpoint=='${LAMBDA_ARN}'].SubscriptionArn | [0]" --output text 2>/dev/null || true)"
  if [ -n "${SUB_ARN}" ] && [ "${SUB_ARN}" != "None" ] && [ "${SUB_ARN}" != "PendingConfirmation" ]; then
    run "SNS 구독 해제: ${SUB_ARN}" \
      aws sns unsubscribe --subscription-arn "${SUB_ARN}" --region "${REGION}"
  else
    echo "  [skip] SNS 구독 없음"
  fi
else
  echo "  [skip] SNS 구독 식별 불가 (Lambda/Topic 미존재)"
fi

# ── 3) Lambda 함수 ───────────────────────────────────────
if [ -n "${LAMBDA_ARN}" ] && [ "${LAMBDA_ARN}" != "None" ]; then
  run "Lambda 삭제: ${FUNCTION_NAME}" \
    aws lambda delete-function --function-name "${FUNCTION_NAME}" --region "${REGION}"
else
  echo "  [skip] Lambda 없음: ${FUNCTION_NAME}"
fi

# ── 4) IAM role (연결 정책 detach → inline 삭제 → role 삭제) ─
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  for parn in $(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
      --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    run "IAM 관리형 정책 detach: ${parn}" \
      aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${parn}"
  done
  for pn in $(aws iam list-role-policies --role-name "${ROLE_NAME}" \
      --query 'PolicyNames[]' --output text 2>/dev/null); do
    run "IAM 인라인 정책 삭제: ${pn}" \
      aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${pn}"
  done
  run "IAM role 삭제: ${ROLE_NAME}" \
    aws iam delete-role --role-name "${ROLE_NAME}"
else
  echo "  [skip] IAM role 없음: ${ROLE_NAME}"
fi

echo ""
if [ "${FORCE}" -eq 1 ]; then
  echo "✅ teardown 완료 (SNS topic '${TOPIC_NAME}' 은 Terraform destroy 에 위임)"
else
  echo "✅ dry-run 종료 — 실제 삭제하려면 --force 를 붙여 다시 실행하세요."
fi
