# Monitoring TODO

## Recovery Hardening

- [ ] CloudWatch Alarm Telegram 알림 연동
  - 흐름: CloudWatch Alarm → SNS → Lambda → Telegram
  - 현재 상태: CloudWatch Alarm → SNS Topic 연결 완료
  - 필요 작업: Lambda, IAM Role, SNS Subscription, Telegram Bot Token / Chat ID 변수 구성

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

- [ ] Recovery Action 비동기 처리 검토
  - 출처: PR #19 Gemini Review
  - 목적: Alertmanager Webhook Timeout 방지
  - 방향: FastAPI BackgroundTasks 또는 Task Queue 구조 검토

- [ ] 운영 컴포넌트 Self-Monitoring 한계 검토
  - 출처: PR #19 Gemini Review
  - 대상: PrometheusDown, AlertmanagerDown
  - 방향: 외부 Health Check 또는 별도 Monitoring 계층 검토

- [x] Recovery Lock / Cooldown 구현 및 강화
  - 목적: 동일 Alert 반복 수신 시 중복 복구 실행 방지
  - 범위: #19 Hardening 반영
  - 방식: active_recoveries 기반 Lock, recovery_state.json 기반 Cooldown 상태 유지

## Alert / Recovery Policy

### 반영 완료

- [x] YAML 파일 확장자 `.yaml` 통일
  - 대상: prometheus, alertmanager, alert_rules, recovery_map

- [x] 운영 컴포넌트 Alert Rule 추가
  - 대상: PrometheusDown, AlertmanagerDown, GrafanaDown, NginxExporterDown

- [x] 운영 컴포넌트 Recovery Policy 추가
  - 대상: PrometheusDown, AlertmanagerDown, GrafanaDown, NginxExporterDown
  - 정책: auto_recovery / notify=false / maintenance.log

- [x] Grafana datasource에 Loki 추가
  - 목적: Recovery / Event Log 조회 기반 구성

- [x] Loki / Promtail 기반 로그 수집 구성
  - 대상: recovery.log, maintenance.log, event.log, critical.log
  - Grafana Explore 쿼리: `{job="recovery-logs"}`

### 확인 필요

- [ ] B Track App 정보 확인 후 BankAppDown 정책 값 확정
  - 확인 필요: App container name, Health endpoint, Prometheus job_name
  - 현재 상태: recovery_map.yaml에 TODO 값으로 선반영

- [ ] Security Alert metric 이름 확정
  - 확인 필요: Login failure metric name, Rate limit metric name
  - 대상: HighLoginFailureRate, RateLimitTriggered

- [ ] PostgresDown 정책 결정
  - 현재 상태: DB 설치/구성 여부 미확인
  - 후보: notify_only / Replica Promote / Failover
  - #19 범위에서는 주석 보류

- [ ] CloudWatch Alarm Grafana 반영 방식 확정
  - 대상: ALB5xxHigh, TargetGroupUnhealthy, TargetGroupUnhealthyGreen, ASGScaleOut
  - 현재 상태: Terraform cloudwatch.tf에 Alarm 정의 존재
  - 방향: Grafana CloudWatch datasource / Alert History 연계

## Dashboard / History

- [x] Recovery 로그 조회 기반 구성
  - Loki / Promtail로 Recovery Controller 로그 수집 확인
  - Grafana Explore에서 `{job="recovery-logs"}` 조회 가능

- [ ] Dashboard Panel 구성
  - Security
  - Application
  - Infrastructure
  - Recovery
  - Event Timeline / Alert History