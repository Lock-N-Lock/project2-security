#!/bin/bash
set -e

sudo dnf install -y fail2ban iptables-services || sudo yum install -y fail2ban iptables-services

sudo mkdir -p /etc/fail2ban/filter.d
sudo mkdir -p /var/log/nginx-container

sudo touch /var/log/nginx-container/access.log
sudo chmod 644 /var/log/nginx-container/access.log

sudo cp /opt/lockbank/docker/fail2ban/jail.local \
    /etc/fail2ban/jail.local

sudo cp /opt/lockbank/docker/fail2ban/filters.d/*.conf \
    /etc/fail2ban/filter.d/

sudo fail2ban-client -t

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

for i in {1..10}; do
  if sudo test -S /var/run/fail2ban/fail2ban.sock; then
    echo "✅ fail2ban socket ready"
    break
  fi

  echo "⏳ waiting fail2ban socket..."
  sleep 1
done

sudo fail2ban-client status
sudo fail2ban-client status nginx-login || true
sudo fail2ban-client status nginx-rate-limit || true