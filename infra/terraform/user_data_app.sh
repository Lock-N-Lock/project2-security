#!/bin/bash
set -uxo pipefail
exec > >(tee -a /var/log/user_data_app.log) 2>&1

# 1. 기본 패키지
dnf install -y iptables docker fail2ban iptables-services

# 2. Tailscale 가입
until curl -fsSL https://tailscale.com/install.sh | sh; do sleep 3; done
systemctl enable --now tailscaled

until TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300"); do sleep 2; done

IID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

HN="${project}-app-$IID"

tailscale up \
  --authkey=${app_join_key} \
  --accept-routes=false \
  --hostname="$HN"

# 3. Docker 준비
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /opt/lockbank
chown -R ec2-user:ec2-user /opt/lockbank

# 4. Docker Hub bootstrap 이미지에서 docker/scripts 꺼내기
docker pull ${docker_user}/lock-bootstrap:latest

docker rm -f lock-bootstrap || true
docker create --name lock-bootstrap ${docker_user}/lock-bootstrap:latest

rm -rf /opt/lockbank/docker /opt/lockbank/scripts
docker cp lock-bootstrap:/bootstrap/docker /opt/lockbank/docker
docker cp lock-bootstrap:/bootstrap/scripts /opt/lockbank/scripts

docker rm lock-bootstrap

chmod +x /opt/lockbank/scripts/*.sh
chown -R ec2-user:ec2-user /opt/lockbank

# 5. 기존 스크립트 재사용
DOCKER_USER="${docker_user}" \
DB_HOST_MAIN="${db_host_main}" \
DB_HOST_REPLICA="${db_host_replica}" \
LOKI_HOST="${loki_host}" \
bash /opt/lockbank/scripts/deploy-app.sh

bash /opt/lockbank/scripts/set-fail2ban.sh

# 6. 상태 확인
docker ps -a || true
fail2ban-client status || true