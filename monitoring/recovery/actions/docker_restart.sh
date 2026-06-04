#!/bin/bash

CONTAINER_NAME="$1"

if [ -z "$CONTAINER_NAME" ]; then
  echo "ERROR: container name is required"
  exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME" > /dev/null; then
  echo "ERROR: container not found: $CONTAINER_NAME"
  exit 1
fi

docker restart "$CONTAINER_NAME"