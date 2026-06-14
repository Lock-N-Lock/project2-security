#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${1:-}"

if [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: container name is required"
  exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME" > /dev/null; then
  echo "ERROR: container not found: $CONTAINER_NAME"
  exit 1
fi

STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")"
echo "INFO: container=$CONTAINER_NAME status_before=$STATUS"

if [ "$STATUS" = "running" ]; then
  docker restart "$CONTAINER_NAME"
else
  docker start "$CONTAINER_NAME"
fi

sleep 2

STATUS_AFTER="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")"
echo "INFO: container=$CONTAINER_NAME status_after=$STATUS_AFTER"

if [ "$STATUS_AFTER" != "running" ]; then
  echo "ERROR: container failed to start: $CONTAINER_NAME"
  exit 1
fi
