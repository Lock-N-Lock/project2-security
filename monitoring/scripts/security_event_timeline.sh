#!/usr/bin/env bash
set -euo pipefail

METRICS_FILE="${METRICS_FILE:-/tmp/nginx_log_metrics.prom}"
LOG_FILE="${LOG_FILE:-logs/security-events.log}"
STATE_FILE="${STATE_FILE:-logs/security-events.state}"

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
status_429="$(metric_value nginx_status_429_count)"
login_401="$(metric_value nginx_login_401_count)"
banned_total="$(metric_value fail2ban_currently_banned_total)"

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
