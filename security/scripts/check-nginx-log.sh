#!/usr/bin/env bash

#==========================================================
# Nginx Access Log 확인 스크립트
# - 최근 Access Log 확인, 401/429 발생 여부 확인
# - JSON 로그 정상 생성 여부 및 Fail2ban 탐지 로그 확인

# 사용 예시 : ./check-nginx-log.sh
#           ./check-nginx-log.sh <<nginx컨테이너>>
#==========================================================

CONTAINER_NAME=${1:-"nginx-security-test"}

echo "[CHECK] Last 20 nginx access logs from ${CONTAINER_NAME}"
echo

sudo docker exec "${CONTAINER_NAME}" tail -n 20 /var/log/nginx/access.log