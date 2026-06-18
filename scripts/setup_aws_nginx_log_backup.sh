#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

APP_HOST="${APP_HOST:-$(tailscale status 2>/dev/null | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')}"
APP_USER="${APP_USER:-ec2-user}"
SSH_KEY_SOURCE="${SSH_KEY_SOURCE:-${PROJECT_DIR}/infra/terraform/lb-key.pem}"
INSTALL_DIR="${INSTALL_DIR:-/opt/lockbank}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-5min}"
METRICS_PORT="${METRICS_PORT:-9105}"
METRICS_INTERVAL="${METRICS_INTERVAL:-30sec}"
METRICS_WORKDIR="${METRICS_WORKDIR:-/tmp}"

if [ -z "${APP_HOST}" ]; then
  echo "[ERROR] APP_HOST is empty. Set APP_HOST=100.x.x.x"
  exit 1
fi

if [ ! -f "${SSH_KEY_SOURCE}" ]; then
  echo "[ERROR] SSH key not found: ${SSH_KEY_SOURCE}"
  exit 1
fi

echo "[INFO] APP_HOST=${APP_HOST}"
echo "[INFO] INSTALL_DIR=${INSTALL_DIR}"

dnf install -y rsync openssh-clients audit policycoreutils policycoreutils-python-utils python3 >/dev/null

mkdir -p "${INSTALL_DIR}/scripts" \
         "${INSTALL_DIR}/keys" \
         "${INSTALL_DIR}/log-backup/aws-nginx"

cp "${SSH_KEY_SOURCE}" "${INSTALL_DIR}/keys/lb-key.pem"
chmod 400 "${INSTALL_DIR}/keys/lb-key.pem"

cat > "${INSTALL_DIR}/scripts/backup_aws_nginx_logs.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

APP_HOST="${APP_HOST}"
APP_USER="${APP_USER}"
SSH_KEY="${INSTALL_DIR}/keys/lb-key.pem"
DEST_DIR="${INSTALL_DIR}/log-backup/aws-nginx"

mkdir -p "\${DEST_DIR}"

rsync -avz --delete \\
  -e "ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no" \\
  "\${APP_USER}@\${APP_HOST}:/var/log/nginx-container/" \\
  "\${DEST_DIR}/"
SCRIPT

chmod +x "${INSTALL_DIR}/scripts/backup_aws_nginx_logs.sh"

cat > /etc/systemd/system/backup-aws-nginx-logs.service <<SERVICE
[Unit]
Description=Backup AWS Nginx Logs to On-Prem Monitoring

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash ${INSTALL_DIR}/scripts/backup_aws_nginx_logs.sh
SERVICE

cat > /etc/systemd/system/backup-aws-nginx-logs.timer <<TIMER
[Unit]
Description=Run AWS Nginx log backup every ${BACKUP_INTERVAL}

[Timer]
OnBootSec=1min
OnUnitActiveSec=${BACKUP_INTERVAL}
Unit=backup-aws-nginx-logs.service

[Install]
WantedBy=timers.target
TIMER

restorecon -Rv "${INSTALL_DIR}" >/dev/null 2>&1 || true

systemctl daemon-reload

echo "[INFO] First run test..."
if ! systemctl start backup-aws-nginx-logs.service; then
  if [ "$(getenforce 2>/dev/null || echo Disabled)" = "Enforcing" ]; then
    echo "[WARN] First run failed under SELinux Enforcing. Generating local SELinux policy from AVC logs..."
    POLICY_WORKDIR="/tmp/lockbank-selinux-policy"
    mkdir -p "${POLICY_WORKDIR}"

    ausearch -m AVC -ts recent | audit2allow -M "${POLICY_WORKDIR}/lockbank_backup"
    semodule -i "${POLICY_WORKDIR}/lockbank_backup.pp"
    restorecon -Rv "${INSTALL_DIR}" >/dev/null 2>&1 || true

    echo "[INFO] Retry after SELinux policy install..."
    systemctl start backup-aws-nginx-logs.service
  else
    echo "[ERROR] Backup service failed. Check: journalctl -u backup-aws-nginx-logs.service -n 80 --no-pager"
    exit 1
  fi
fi

systemctl enable --now backup-aws-nginx-logs.timer

cat > /etc/systemd/system/nginx-log-metrics-exporter.service <<EXPORTER_SERVICE
[Unit]
Description=Serve nginx log metrics on port ${METRICS_PORT}
After=network.target

[Service]
Type=simple
WorkingDirectory=${METRICS_WORKDIR}
ExecStart=/usr/bin/python3 -m http.server ${METRICS_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EXPORTER_SERVICE

cat > /etc/systemd/system/nginx-log-metrics-generate.service <<GENERATE_SERVICE
[Unit]
Description=Generate nginx log metrics prom file

[Service]
Type=oneshot
WorkingDirectory=${PROJECT_DIR}
Environment=PROJECT_DIR=${PROJECT_DIR}
Environment=APP_HOST=${APP_HOST}
Environment=APP_USER=${APP_USER}
Environment=SSH_KEY=${INSTALL_DIR}/keys/lb-key.pem
ExecStart=/bin/bash ${PROJECT_DIR}/monitoring/scripts/nginx_log_metrics.sh
GENERATE_SERVICE

cat > /etc/systemd/system/nginx-log-metrics-generate.timer <<GENERATE_TIMER
[Unit]
Description=Generate nginx log metrics every ${METRICS_INTERVAL}

[Timer]
OnBootSec=${METRICS_INTERVAL}
OnUnitActiveSec=${METRICS_INTERVAL}
Unit=nginx-log-metrics-generate.service

[Install]
WantedBy=timers.target
GENERATE_TIMER

systemctl daemon-reload
systemctl enable --now nginx-log-metrics-exporter.service
systemctl enable --now nginx-log-metrics-generate.timer
systemctl start nginx-log-metrics-generate.service

echo "[OK] AWS Nginx log backup configured."
echo "[OK] Backup path: ${INSTALL_DIR}/log-backup/aws-nginx/"
echo "[OK] Timer: backup-aws-nginx-logs.timer"
echo "[OK] Metrics exporter: ${METRICS_PORT}"
echo "[OK] Metrics timer: nginx-log-metrics-generate.timer"
