# Monitoring TODO

## Recovery

- [ ] docker inspect 기반 조회 리팩토링
  - 출처: PR #10 Review
  - 답변: "추후 리팩토링 단계에서 검토"

- [ ] recovery_map.yaml 캐싱 적용 검토
  - 출처: PR #10 Review
  - 답변: "캐싱 개선은 Hardening 단계에서 검토"

- [ ] recovery_map.yaml 로딩 예외 처리 개선
  - 출처: PR #10 Review
  - 답변: "예외 처리 개선은 Hardening 단계에서 검토"

- [ ] 표준 Python logging 적용 검토
  - 출처: PR #10 Review
  - 답변: "표준 logging + RotatingFileHandler 교체 검토"

- [ ] docker.sock 권한 제한
  - 출처: PR #14 Gemini Review
  - 답변: "docker-socket-proxy 또는 권한 제한 구조 검토"

## Alert / Recovery Policy

- [ ] B Track App 정보 확인 후 BankAppDown 정책 값 확정
- 확인 필요: App container name, Health endpoint, Prometheus job_name
- 현재 상태: recovery_map.yaml에 TODO 값으로 선반영

- [ ] Security Alert metric 이름 확정
- 확인 필요: Login failure metric name, Rate limit metric name
- 대상: HighLoginFailureRate, RateLimitTriggered

- [ ] 운영 컴포넌트 복구 정책 확정
- 대상: GrafanaDown, AlertmanagerDown
- 확인 필요: 실제 container name, verify URL, Telegram 알림 여부

- [ ] Recovery Lock 구현
- 목적: 동일 Alert 반복 수신 시 중복 복구 실행 방지
- 범위: #19 Hardening 작업

- [ ] PostgresDown 정책 결정
- 후보: notify_only / Replica Promote / Failover
- 현재 상태: #19 범위에서는 보류