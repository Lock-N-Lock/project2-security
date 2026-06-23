#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
METRICS_FILE="${METRICS_FILE:-/tmp/nginx_log_metrics.prom}"
LOG_FILE="${LOG_FILE:-${MONITORING_DIR}/logs/security-events.log}"
STATE_FILE="${STATE_FILE:-${MONITORING_DIR}/logs/security-events.state}"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
touch "$STATE_FILE"

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

metric_value() {
  local name="$1"
  awk -v n="$name" '$1 == n {print int($2); found=1} END {if (!found) print 0}' "$METRICS_FILE"
}

state_get() {
  local key="$1"
  grep -E "^${key}=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2 || echo "0"
}

state_set() {
  local key="$1"
  local value="$2"
  touch "$STATE_FILE"
  if grep -qE "^${key}=" "$STATE_FILE"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$STATE_FILE"
  else
    echo "${key}=${value}" >> "$STATE_FILE"
  fi
}

emit_transition() {
  local key="$1"
  local active="$2"
  local level="$3"
  local event_name="$4"
  local detail="$5"

  local previous
  previous="$(state_get "$key")"

  if [ "$previous" != "$active" ]; then
    if [ "$active" = "1" ]; then
      echo "[$(now)] [${level}] security event: ${event_name}, ${detail}" >> "$LOG_FILE"
    else
      echo "[$(now)] [INFO] security resolved: ${event_name}, ${detail}" >> "$LOG_FILE"
    fi
    state_set "$key" "$active"
  fi
}

status_401="$(metric_value nginx_status_401_count)"
status_401="${status_401:-0}"
status_429="$(metric_value nginx_status_429_count)"
status_429="${status_429:-0}"
login_401="$(metric_value nginx_login_401_count)"
login_401="${login_401:-0}"
banned_total="$(metric_value fail2ban_currently_banned_total)"
banned_total="${banned_total:-0}"

if [ "$status_401" -gt 0 ] || [ "$login_401" -gt 0 ]; then
  emit_transition "HighLoginFailureRate" "1" "WARN" "HighLoginFailureRate" "status_401=${status_401}, login_401=${login_401}"
else
  emit_transition "HighLoginFailureRate" "0" "WARN" "HighLoginFailureRate" "status_401=0, login_401=0"
fi

if [ "$status_429" -gt 0 ]; then
  emit_transition "RateLimitTriggered" "1" "WARN" "RateLimitTriggered" "status_429=${status_429}"
else
  emit_transition "RateLimitTriggered" "0" "WARN" "RateLimitTriggered" "status_429=0"
fi

if [ "$banned_total" -gt 0 ]; then
  emit_transition "Fail2BanActive" "1" "CRITICAL" "Fail2BanActive" "banned_total=${banned_total}"
else
  emit_transition "Fail2BanActive" "0" "CRITICAL" "Fail2BanActive" "banned_total=0"
fi


FAIL2BAN_LOG_FILE="${FAIL2BAN_LOG_FILE:-${MONITORING_DIR}/logs/aws-nginx/fail2ban.log}"
FAIL2BAN_STATE_FILE="${FAIL2BAN_STATE_FILE:-${MONITORING_DIR}/logs/fail2ban-events.state}"

APP_HOST="${APP_HOST:-$(tailscale status 2>/dev/null | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')}"
APP_USER="${APP_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-${PROJECT_DIR:-$(pwd)}/infra/terraform/lb-key.pem}"
REMOTE_FAIL2BAN_LOG_FILE="${REMOTE_FAIL2BAN_LOG_FILE:-/var/log/fail2ban.log}"
FAIL2BAN_RUNTIME_LOG_FILE="$FAIL2BAN_LOG_FILE"

fetch_remote_fail2ban_log() {
  if [ -z "${APP_HOST}" ] || [ ! -f "${SSH_KEY}" ]; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  if sudo ssh -i "${SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o BatchMode=yes \
      "${APP_USER}@${APP_HOST}" \
      "sudo test -f '${REMOTE_FAIL2BAN_LOG_FILE}' && sudo cat '${REMOTE_FAIL2BAN_LOG_FILE}'" > "$tmp" 2>/dev/null; then
    FAIL2BAN_RUNTIME_LOG_FILE="$tmp"
  else
    rm -f "$tmp"
  fi
}

process_fail2ban_events() {
  fetch_remote_fail2ban_log
  [ -f "$FAIL2BAN_RUNTIME_LOG_FILE" ] || return 0
  local last_line total start
  total="$(wc -l < "$FAIL2BAN_RUNTIME_LOG_FILE")"

  if [ ! -f "$FAIL2BAN_STATE_FILE" ]; then
    echo "$total" > "$FAIL2BAN_STATE_FILE"
    if [ "$FAIL2BAN_RUNTIME_LOG_FILE" != "$FAIL2BAN_LOG_FILE" ]; then
      rm -f "$FAIL2BAN_RUNTIME_LOG_FILE"
    fi
    return 0
  fi

  last_line="$(cat "$FAIL2BAN_STATE_FILE" 2>/dev/null || echo 0)"

  if [ "$total" -lt "$last_line" ]; then
    last_line=0
  fi

  start=$((last_line + 1))

  tail -n +"$start" "$FAIL2BAN_RUNTIME_LOG_FILE" | while read -r line; do
    if [[ "$line" =~ \[([^]]+)\]\ Ban\ ([0-9a-fA-F:.]+) ]]; then
      jail="${BASH_REMATCH[1]}"
      ip="${BASH_REMATCH[2]}"
      echo "[$(now)] [CRITICAL] security event: IPBanned, jail=${jail}, ip=${ip}" >> "$LOG_FILE"
    elif [[ "$line" =~ \[([^]]+)\]\ Unban\ ([0-9a-fA-F:.]+) ]]; then
      jail="${BASH_REMATCH[1]}"
      ip="${BASH_REMATCH[2]}"
      echo "[$(now)] [INFO] security event: IPUnbanned, jail=${jail}, ip=${ip}" >> "$LOG_FILE"
    fi
  done

  echo "$total" > "$FAIL2BAN_STATE_FILE"
  if [ "$FAIL2BAN_RUNTIME_LOG_FILE" != "$FAIL2BAN_LOG_FILE" ]; then
    rm -f "$FAIL2BAN_RUNTIME_LOG_FILE"
  fi
}

process_fail2ban_events
