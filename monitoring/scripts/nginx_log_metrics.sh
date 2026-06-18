#!/bin/bash
set -euo pipefail

OUT="/tmp/nginx_log_metrics.prom"
LOKI="http://localhost:3100"

query_count() {
  local q="$1"
  curl -G -s "${LOKI}/loki/api/v1/query" \
    --data-urlencode "query=${q}" \
  | jq -r '.data.result[0].value[1] // "0"'
}

STATUS_401=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":401" [1m]))')
STATUS_429=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"status\":429" [1m]))')
LOGIN_401=$(query_count 'sum(count_over_time({job="nginx-access"} |= "\"uri\":\"/login\"" |= "\"status\":401" [1m]))')

cat > "$OUT" <<EOF
# HELP nginx_status_401_count Nginx access log HTTP 401 count in last 1 minute
# TYPE nginx_status_401_count gauge
nginx_status_401_count ${STATUS_401}

# HELP nginx_status_429_count Nginx access log HTTP 429 count in last 1 minute
# TYPE nginx_status_429_count gauge
nginx_status_429_count ${STATUS_429}

# HELP nginx_login_401_count Nginx /login HTTP 401 count in last 1 minute
# TYPE nginx_login_401_count gauge
nginx_login_401_count ${LOGIN_401}
EOF

cat "$OUT"
