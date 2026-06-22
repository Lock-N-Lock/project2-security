#!/bin/bash
set -e

: "${DOCKER_USER:?DOCKER_USER is required}"
: "${DB_HOST_MAIN:?DB_HOST_MAIN is required}"
: "${DB_HOST_REPLICA:?DB_HOST_REPLICA is required}"

echo "🚀 Deploy App Containers"

docker rm -f lb-fastapi lb-security-nginx lb-nginx-exporter lb-promtail || true

docker network create lb-net || true

sudo mkdir -p /var/log/nginx-container
sudo touch /var/log/nginx-container/access.log /var/log/nginx-container/error.log
sudo chmod 644 /var/log/nginx-container/*.log

docker pull "${DOCKER_USER}/lock-app:latest"
docker pull "${DOCKER_USER}/lock-security-nginx:latest"
docker pull nginx/nginx-prometheus-exporter:latest
docker pull grafana/promtail:2.9.8

docker run -d --restart=always --net lb-net --name lb-fastapi \
  -e DB_HOST_MAIN="${DB_HOST_MAIN}" \
  -e DB_HOST_REPLICA="${DB_HOST_REPLICA}" \
  -e DB_USER=lb-user \
  -e DB_PASSWORD=lb-user \
  -e DB_NAME=lb-db \
  -e SECRET_KEY=${SECRET_KEY:-$(openssl rand -hex 32)} \
  "${DOCKER_USER}/lock-app:latest"

docker run -d --restart=always --net lb-net --name lb-security-nginx \
  -p 80:80 \
  -v /var/log/nginx-container:/var/log/nginx \
  "${DOCKER_USER}/lock-security-nginx:latest"

docker run -d --restart=always --net lb-net --name lb-nginx-exporter \
  -p 9113:9113 \
  nginx/nginx-prometheus-exporter:latest \
  -nginx.scrape-uri=http://lb-security-nginx/stub_status

docker run -d --restart=always --net lb-net --name lb-promtail \
  -v /var/log/nginx-container:/var/log/nginx:ro \
  -v /opt/lockbank/docker/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro \
  -e LOKI_HOST="${DB_HOST_REPLICA}" \
  grafana/promtail:2.9.8 \
  -config.file=/etc/promtail/promtail-config.yaml \
  -config.expand-env=true

docker ps -a