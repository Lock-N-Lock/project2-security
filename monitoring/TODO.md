# Monitoring TODO

## Recovery

- [ ] docker inspect 기반 조회 리팩토링
  - 출처: PR #10 Review
  - 답변: "추후 리팩토링 단계에서 검토"

- [ ] recovery_map.yml 캐싱 적용 검토
  - 출처: PR #10 Review
  - 답변: "캐싱 개선은 Hardening 단계에서 검토"

- [ ] recovery_map.yml 로딩 예외 처리 개선
  - 출처: PR #10 Review
  - 답변: "예외 처리 개선은 Hardening 단계에서 검토"

- [ ] 표준 Python logging 적용 검토
  - 출처: PR #10 Review
  - 답변: "표준 logging + RotatingFileHandler 교체 검토"

- [ ] docker.sock 권한 제한
  - 출처: PR #14 Gemini Review
  - 답변: "docker-socket-proxy 또는 권한 제한 구조 검토"