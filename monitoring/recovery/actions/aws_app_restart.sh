#!/bin/bash
set -euo pipefail

AWS_APP_PRIVATE_IP="${AWS_APP_PRIVATE_IP:-}"
AWS_BASTION_PUBLIC_IP="${AWS_BASTION_PUBLIC_IP:-}"
AWS_SSH_KEY_PATH="${AWS_SSH_KEY_PATH:-/app/ssh/lb-key.pem}"
AWS_SSH_USER="${AWS_SSH_USER:-ec2-user}"

DB_HOST_MAIN="${DB_HOST_MAIN:-}"
DB_HOST_REPLICA="${DB_HOST_REPLICA:-}"
DB_PORT="${DB_PORT:-5432}"
DB_REPLICA_CONTAINER="${DB_REPLICA_CONTAINER:-lb-postgres-replica}"
NGINX_CONTAINER="${NGINX_CONTAINER:-lb-security-nginx}"

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

check_tcp() {
  local host="$1"
  local port="$2"
  [ -n "$host" ] || return 0

  if command -v nc >/dev/null 2>&1; then
    nc -z -w 3 "$host" "$port"
  else
    timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}"
  fi
}

wait_tcp() {
  local host="$1"
  local port="$2"
  local retries="${3:-10}"

  [ -n "$host" ] || return 0

  for i in $(seq 1 "$retries"); do
    if check_tcp "$host" "$port"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

if [ -n "$DB_HOST_REPLICA" ] && ! check_tcp "$DB_HOST_REPLICA" "$DB_PORT"; then
  echo "WARN: replica DB is not reachable: ${DB_HOST_REPLICA}:${DB_PORT}"

  if sudo docker ps -a --format "{{.Names}}" | grep -qx "$DB_REPLICA_CONTAINER"; then
    echo "INFO: starting local replica DB container: ${DB_REPLICA_CONTAINER}"
    sudo docker start "$DB_REPLICA_CONTAINER" >/dev/null || true
  fi

  if ! wait_tcp "$DB_HOST_REPLICA" "$DB_PORT" 10; then
    echo "ERROR: replica DB is still not reachable: ${DB_HOST_REPLICA}:${DB_PORT}"
    exit 1
  fi
fi

REMOTE_CHECK_MAIN_DB=""
if [ -n "$DB_HOST_MAIN" ]; then
  REMOTE_CHECK_MAIN_DB="timeout 3 bash -c 'cat < /dev/null > /dev/tcp/${DB_HOST_MAIN}/${DB_PORT}'"
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
  "if [ -n \"${REMOTE_CHECK_MAIN_DB}\" ]; then \
     ${REMOTE_CHECK_MAIN_DB} || { echo 'ERROR: main DB is not reachable from app host: ${DB_HOST_MAIN}:${DB_PORT}'; exit 1; }; \
   fi && \
   if [ \"\$(sudo docker inspect -f '{{.State.Status}}' '${CONTAINER_NAME}')\" = 'running' ]; then \
     sudo docker restart '${CONTAINER_NAME}'; \
   else \
     sudo docker start '${CONTAINER_NAME}'; \
   fi && \
   NET=\$(sudo docker inspect '${NGINX_CONTAINER}' --format '{{range \$name, \$conf := .NetworkSettings.Networks}}{{println \$name}}{{end}}' | head -1); \
   if [ -n \"\$NET\" ]; then sudo docker network connect \"\$NET\" '${CONTAINER_NAME}' 2>/dev/null || true; fi && \
   sudo docker inspect -f '{{.State.Status}}' '${CONTAINER_NAME}' | grep -w running"
