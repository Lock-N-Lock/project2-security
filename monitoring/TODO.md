# Monitoring TODO

## Notification

- [ ] Telegram Bot 구성
  - Bot 생성
  - 운영 채널/그룹 생성
  - Chat ID 확인

- [ ] Alertmanager → Telegram 연동
  - 운영 컴포넌트 Alert 기준 테스트
  - 대상:
    - PrometheusDown
    - AlertmanagerDown
    - GrafanaDown
    - NginxExporterDown

- [ ] Alert Severity 기준 정리
  - Critical
  - Warning
  - Info

- [ ] Telegram Message Template 정리
  - Alert Name
  - Severity
  - Summary
  - Recovery Status

- [ ] Alert Inventory 작성
  - Alert
  - Severity
  - Auto Recovery 여부
  - Verify 방식
  - Dashboard 위치

## Recovery Hardening

- [ ] CloudWatch Alarm Telegram 알림 연동
  - 흐름: CloudWatch Alarm → SNS → Lambda → Telegram
  - 현재 상태: CloudWatch Alarm → SNS Topic 연결 완료
  - 필요 작업:
    - Lambda
    - IAM Role
    - SNS Subscription
    - Telegram Bot Token / Chat ID 변수 구성
  - 우선순위: 후순위

- [ ] docker inspect 기반 조회 리팩토링
  - 출처: PR #10 Review
  - 답변: "추후 리팩토링 단계에서 검토"

- [x] recovery_map.yaml 캐싱 적용 검토
  - 출처: PR #10 Review

- [x] recovery_map.yaml 로딩 예외 처리 개선
  - 출처: PR #10 Review

- [x] 표준 Python logging 적용 검토
  - 출처: PR #10 Review

- [ ] docker.sock 권한 제한
  - 출처: PR #14 Gemini Review
  - 답변: "docker-socket-proxy 또는 권한 제한 구조 검토"

- [x] Recovery Action 비동기 처리 검토
  - 출처: PR #19 Gemini Review

- [x] 운영 컴포넌트 Self-Monitoring 한계 검토
  - 출처: PR #19 Gemini Review

- [x] Recovery Lock / Cooldown 구현 및 강화
  - 범위: #19 Hardening 반영

## Alert / Recovery Policy

### 반영 완료

- [x] YAML 파일 확장자 `.yaml` 통일

- [x] 운영 컴포넌트 Alert Rule 추가
  - PrometheusDown
  - AlertmanagerDown
  - GrafanaDown
  - NginxExporterDown

- [x] 운영 컴포넌트 Recovery Policy 추가
  - auto_recovery
  - notify=false
  - maintenance.log

- [x] Grafana datasource에 Loki 추가

- [x] Loki / Promtail 기반 로그 수집 구성

### 확인 필요

- [ ] B Track App 정보 확인 후 BankAppDown 정책 값 확정
  - App container name
  - Health endpoint
  - Prometheus job_name

- [ ] Security Alert Metric 이름 확정
  - Login Failure Metric
  - Rate Limit Metric

- [ ] PostgresDown / PostgresExporterDown Recovery Policy 활성화

  확인 필요:
  - DB container name
  - PostgreSQL Exporter container name
  - 원격 실행 방식(Remote Adapter)

  Verify:
  - PostgresDown → pg_isready
  - PostgresExporterDown → metrics endpoint 또는 Prometheus up

  제외:
  - Replica Promote
  - Failover
  - DB 연결 정보 전환

  필요 작업:
  - Recovery Policy 값 확정
  - 통합 테스트

## Dashboard / History

- [x] Recovery 로그 조회 기반 구성

- [x] Dashboard Panel 구성
  - Security
  - Application
  - Infrastructure
  - Recovery

- [x] Dashboard Provisioning 구성 및 검증

- [x] Recovery Metrics 구성
  - recovery_attempt_total
  - recovery_success_total

### 확인 필요

- [ ] CloudWatch Alarm Dashboard 반영 범위 확정

  대상:
  - ALB5xxHigh
  - TargetGroupUnhealthy
  - TargetGroupUnhealthyGreen
  - ASGScaleOut

  논의사항:
  - Dashboard 패널 표시
  - Alert History 표시
  - MVP 제외 여부

- [ ] Dashboard 시나리오 매핑 정리

  시나리오:
  - 로그인 공격
  - API Flooding
  - 트래픽 증가 / ASG
  - App 장애
  - DB 장애
  - 안전 배포

  목적:
  - 발표 자료 연계
  - Dashboard 설명 자료 정리

- [ ] Monitoring & Recovery Quick Guide 작성

  포함 내용:
  - 전체 흐름
    - Prometheus
    - Alertmanager
    - Telegram
    - Recovery Controller
    - Loki
    - Grafana

  - Auto Recovery vs Notify Only

  - CloudWatch vs Prometheus 역할 구분

  - Dashboard 섹션 설명

  - 주요 Alert 설명