#!/bin/bash
set -euo pipefail

AWS_APP_PRIVATE_IP="${AWS_APP_PRIVATE_IP:-}"
AWS_BASTION_PUBLIC_IP="${AWS_BASTION_PUBLIC_IP:-}"
AWS_SSH_KEY_PATH="${AWS_SSH_KEY_PATH:-/app/ssh/lb-key.pem}"
AWS_SSH_USER="${AWS_SSH_USER:-ec2-user}"

CONTAINER_NAME="${1:-}"


if command -v aws >/dev/null 2>&1; then
  DYNAMIC_APP_PRIVATE_IP="$(
    aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=lb-app*" "Name=instance-state-name,Values=running" \
      --query "Reservations[].Instances[].PrivateIpAddress | [0]" \
      --output text 2>/dev/null || true
  )"

  if [ -n "$DYNAMIC_APP_PRIVATE_IP" ] && [ "$DYNAMIC_APP_PRIVATE_IP" != "None" ]; then
    AWS_APP_PRIVATE_IP="$DYNAMIC_APP_PRIVATE_IP"
  fi
fi

if [ -z "$AWS_APP_PRIVATE_IP" ]; then
  echo "ERROR: AWS_APP_PRIVATE_IP is required"
  exit 1
fi

if [ -z "$AWS_BASTION_PUBLIC_IP" ]; then
  echo "ERROR: AWS_BASTION_PUBLIC_IP is required"
  exit 1
fi

if [ ! -f "$AWS_SSH_KEY_PATH" ]; then
  echo "ERROR: SSH key not found: $AWS_SSH_KEY_PATH"
  exit 1
fi

REMOTE_FIND_CONTAINER='
if [ -n "'"$CONTAINER_NAME"'" ]; then
  echo "'"$CONTAINER_NAME"'"
else
  sudo docker ps -a --format "{{.Names}}" \
  | grep -E "lockbank-app|lb-fastapi|fastapi|app" \
  | head -1
fi
'

CONTAINER_NAME="$(
ssh -i "$AWS_SSH_KEY_PATH" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/tmp/known_hosts \
  -o ProxyCommand="ssh -i $AWS_SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/known_hosts -W %h:%p ${AWS_SSH_USER}@${AWS_BASTION_PUBLIC_IP}" \
  "${AWS_SSH_USER}@${AWS_APP_PRIVATE_IP}" \
  "$REMOTE_FIND_CONTAINER"
)"

if [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: app container not found"
  exit 1
fi

echo "INFO: remote app restart target=${AWS_APP_PRIVATE_IP} container=${CONTAINER_NAME}"

ssh -i "$AWS_SSH_KEY_PATH" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/tmp/known_hosts \
  -o ProxyCommand="ssh -i $AWS_SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/known_hosts -W %h:%p ${AWS_SSH_USER}@${AWS_BASTION_PUBLIC_IP}" \
  "${AWS_SSH_USER}@${AWS_APP_PRIVATE_IP}" \
  "if [ \"\$(sudo docker inspect -f '{{.State.Status}}' '${CONTAINER_NAME}')\" = 'running' ]; then \
     sudo docker restart '${CONTAINER_NAME}'; \
   else \
     sudo docker start '${CONTAINER_NAME}'; \
   fi && \
   sudo docker inspect -f '{{.State.Status}}' '${CONTAINER_NAME}' | grep -w running"
