#!/bin/bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
OUT="${OUT:-/tmp/nginx_log_metrics.prom}"
LOKI="${LOKI:-http://localhost:3100}"

APP_HOST="${APP_HOST:-$(tailscale status 2>/dev/null | awk '/lb-app-i-/ && $0 !~ /offline/ {print $1; exit}')}"
APP_USER="${APP_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-${PROJECT_DIR}/infra/terraform/lb-key.pem}"

query_count() {
  local q="$1"
  curl -G -s "${LOKI}/loki/api/v1/query" \
    --data-urlencode "query=${q}" \
  | jq -r '.data.result[0] | if . then .value[1] else "0" end'
}

fetch_fail2ban_stats() {
  if [ -z "${APP_HOST}" ] || [ ! -f "${SSH_KEY}" ]; then
    echo "0 0"
    return
  fi

  read -r banned_login banned_ratelimit < <(
    ssh -i "${SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o BatchMode=yes \
      "${APP_USER}@${APP_HOST}" \
      'for jail in nginx-login nginx-rate-limit; do
        val=$(sudo fail2ban-client status "$jail" | awk -F: '\''/Currently banned/ {gsub(/ /, "", $2); print $2}'\'')
        printf "%s " "${val:-0}"
      done' 2>/dev/null || echo "0 0"
    )

  echo "${banned_login:-0} ${banned_ratelimit:-0}"
}


STATUS_401=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":401" [2m]))')
STATUS_401="${STATUS_401:-0}"
if ! [[ "$STATUS_401" =~ ^[0-9]+$ ]]; then STATUS_401=0; fi
STATUS_429=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":429" [2m]))')
STATUS_429="${STATUS_429:-0}"
if ! [[ "$STATUS_429" =~ ^[0-9]+$ ]]; then STATUS_429=0; fi
LOGIN_401=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"uri\":\"/login\"" |= "\"status\":401" [2m]))')
LOGIN_401="${LOGIN_401:-0}"
if ! [[ "$LOGIN_401" =~ ^[0-9]+$ ]]; then LOGIN_401=0; fi
STATUS_200=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":200" [2m]))')
STATUS_200="${STATUS_200:-0}"
if ! [[ "$STATUS_200" =~ ^[0-9]+$ ]]; then STATUS_200=0; fi
STATUS_500=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":500" [2m]))')
STATUS_500="${STATUS_500:-0}"
if ! [[ "$STATUS_500" =~ ^[0-9]+$ ]]; then STATUS_500=0; fi

read -r F2B_LOGIN_BANNED F2B_RATELIMIT_BANNED <<< "$(fetch_fail2ban_stats)"

F2B_LOGIN_BANNED="${F2B_LOGIN_BANNED:-0}"
F2B_RATELIMIT_BANNED="${F2B_RATELIMIT_BANNED:-0}"
F2B_TOTAL_BANNED=$((F2B_LOGIN_BANNED + F2B_RATELIMIT_BANNED))

cat > "$OUT" <<METRICS
# HELP nginx_status_200_count Nginx access log HTTP 200 count in last 2 minutes
# TYPE nginx_status_200_count gauge
nginx_status_200_count ${STATUS_200}

# HELP nginx_status_401_count Nginx access log HTTP 401 count in last 2 minutes
# TYPE nginx_status_401_count gauge
nginx_status_401_count ${STATUS_401}

# HELP nginx_status_429_count Nginx access log HTTP 429 count in last 2 minutes
# TYPE nginx_status_429_count gauge
nginx_status_429_count ${STATUS_429}

# HELP nginx_status_500_count Nginx access log HTTP 500 count in last 2 minutes
# TYPE nginx_status_500_count gauge
nginx_status_500_count ${STATUS_500}

# HELP nginx_login_401_count Nginx /login HTTP 401 count in last 2 minutes
# TYPE nginx_login_401_count gauge
nginx_login_401_count ${LOGIN_401}

# HELP fail2ban_currently_banned_login Currently banned IPs in nginx-login jail
# TYPE fail2ban_currently_banned_login gauge
fail2ban_currently_banned_login ${F2B_LOGIN_BANNED}

# HELP fail2ban_currently_banned_ratelimit Currently banned IPs in nginx-rate-limit jail
# TYPE fail2ban_currently_banned_ratelimit gauge
fail2ban_currently_banned_ratelimit ${F2B_RATELIMIT_BANNED}

# HELP fail2ban_currently_banned_total Total currently banned IPs
# TYPE fail2ban_currently_banned_total gauge
fail2ban_currently_banned_total ${F2B_TOTAL_BANNED}
METRICS

if [ "${DEBUG_METRICS:-0}" = "1" ]; then
  cat "$OUT"
fi