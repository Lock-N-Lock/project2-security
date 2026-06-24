#!/usr/bin/env bash

#==========================================================
# Login Attack / Rate Limit 검증 스크립트
# 로그인 공격 시뮬레이션 및 401 발생 확인, Nginx Rate Limit 동작 확인
# 429 발생 확인 및 Fail2ban 탐지 조건 생성
#
# 사용 예시 : ./test-rate-limit.sh
#           ./test-rate-limit.sh http://10.0.1.14
# 429 발생 시 --> Rate Limit 정상 동작
#==========================================================

TARGET_URL=${1:-"http://localhost:8080"}

echo "[TEST] Login attack rate limit test"
echo "Target: ${TARGET_URL}/login"
echo

for i in {1..20}
do
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${TARGET_URL}/login" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Security-Test-Login-Attack" \
    -d '{"username":"user1","password":"wrong"}')

  echo "request=${i} status=${code}"
done

echo
echo "[RESULT] If 429 appears, Nginx Rate Limit is working."