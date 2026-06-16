#!/usr/bin/env bash
set -euo pipefail

DOCKER_USER="${DOCKER_USER:-zeongni}"

docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
docker buildx create --name multiarch --driver docker-container --use 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap

# 변경 후 (--build-arg 추가)
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg GITHUB_ACTOR="${GITHUB_ACTOR:-${USER:-unknown}}" \
  -t "${DOCKER_USER}/lock-app:latest" \
  --push ./docker/app

docker buildx build --platform linux/amd64,linux/arm64 \
  -t "${DOCKER_USER}/lock-security-nginx:latest" \
  --push ./docker/nginx

docker buildx build --platform linux/amd64,linux/arm64 \
  -t "${DOCKER_USER}/lock-fail2ban:latest" \
  --push ./docker/fail2ban