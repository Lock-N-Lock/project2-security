# Monitoring TODO

## Notification

### 최우선

* [] CloudWatch Datasource 인증 구성
  - Grafana CloudWatch Dashboard 활성화
  - CPU Usage
  - ALB Target Health
  - ASG Instance Count

* [ ] Recovery Success 알림 구현

  대상:
  - user_service category
  - 예: BankAppDown

  제외:
  - maintenance category
  - security category

  메시지 예시:
  - ✅ 복구 완료
  - 은행 서비스 장애 (BankAppDown)
  - 대상
  - 시도 횟수
  - 복구 결과

  후속 개선:
  - 복구 소요시간 표시

* [ ] Telegram Message Template 정리

  * 한글 메시지 통일
  * Alert Name 표시 방식
  * Status 표시 방식
  * Grouped Alert 표시 방식
  * Severity / Service / Instance 포함 여부 확정

* [ ] Alert Inventory 작성

  * Alert
  * Severity
  * Auto Recovery 여부
  * Verify 방식
  * Dashboard 위치

### 후순위

* [ ] Alert Severity 기준 정리

  * Critical
  * Warning
  * Info

* [ ] Telegram 설정 가이드 작성

  * .env.example 제공
  * TELEGRAM_BOT_TOKEN
  * TELEGRAM_CHAT_ID
  * 개인 환경 적용 방법 문서화

* [ ] Notification Channel 운영 정책 문서화

  * 개인 테스트 채널
  * 팀 공용 채널
  * 최종 시연 환경 적용 기준 정리

* [ ] CloudWatch Notification Channel 통합 검토

  현재:
  - CloudWatch Alarm → SNS → Lambda → Telegram

  향후 검토:
  - CloudWatch Alarm → SNS → Lambda → telegram-notifier → Telegram

  기대 효과:
  - Telegram 메시지 템플릿 통일
  - Bot Token 관리 일원화
  - Notification 로직 통합

  검토 사항:
  - Lambda → on-mgmt 접근 방식
  - 네트워크 구성
  - 장애 지점 증가 여부

  우선순위: Low

### 완료

* [x] Notification Channel 운영 정책 정리

  * maintenance Alert 정책 확정
  * User Service Alert 정책 확정
  * Security Alert 정책 확정
  * Telegram 발송 기준 정리

* [x] Alertmanager → Telegram Route 정리

  * maintenance Alert → Telegram 제외
  * Recovery Webhook 유지
  * Route 검증

* [x] Recovery 실패 알림 설계 및 구현

  * Retry 3회 후 Verify 실패 시 알림
  * Recovery Controller → telegram-notifier 호출 방식 채택
  * telegram-notifier `/recovery-failed` API 추가
  * API 단독 테스트 완료

* [x] Telegram Bot 구성

  * Bot 생성
  * 운영 채널/그룹 생성
  * Chat ID 확인

* [x] Alertmanager → Telegram 연동

  * 운영 컴포넌트 Alert 기준 테스트
  * 대상:

    * PrometheusDown
    * AlertmanagerDown
    * GrafanaDown
    * NginxExporterDown

---

## Recovery Hardening

### 우선순위

* [ ] ASG 환경에서 Recovery Target 동적 식별 방식 검토

  배경:

  * BankAppDown 검증 중 App 컨테이너 중지 이후 ALB Health Check 실패 발생
  * ASG가 기존 App 인스턴스를 Unhealthy로 판단하고 신규 인스턴스로 교체하는 동작 확인
  * ASG 환경에서는 App 인스턴스가 고정 대상이 아니므로 Remote Adapter가 고정 Host 기준으로 동작하면 복구 대상이 사라질 수 있음

  검토:

  * Prometheus alert의 instance label 기반 대상 식별
  * Tailscale Service Discovery 결과 기반 대상 식별
  * AWS Target Group / ASG 인스턴스 목록 기반 대상 재조회
  * ASG 인스턴스 교체와 Recovery Controller 컨테이너 복구의 역할 경계

  비고:

  * 2026-06-13 BankAppDown E2E 검증 중 확인
  * #22 Nginx Security Layer 반영 후 최종 App 구조 기준으로 재검토

  ---

  동적 대상 식별까지 제대로 하면 최소 반나절~하루는 잡는 게 현실적. 
  AWS Target Group/ASG 조회까지 넣으면 IAM 권한, AWS CLI 설정, 대상 선택 로직, 예외 처리까지 봐야 해서 더 걸릴 수 있음.

* [ ] Recovery Verify Timing 정책 추가

  배경:

  * BankAppDown 검증 과정에서 Recovery Action 직후 Verify가 수행됨
  * App 기동 전 Verify가 실행되어 False Negative 발생 가능

  검토:

  * verify_delay
    - Action 실행 후 Verify 전 대기 시간

  * retry_interval
    - Verify 실패 후 다음 Retry 전 대기 시간

  적용 대상:

  * BankAppDown
  * PostgresDown
  * PostgresExporterDown

  비고:

  * 2026-06-13 E2E 검증 중 확인

* [ ] BankAppDown End-to-End 검증

  검증 흐름:

  * App Container 중지
  * Prometheus Alert 발생
  * Alertmanager 수신
  * Recovery Controller 수신
  * Recovery Action 실행
  * Verify 성공 확인

  확인 항목:

  * Alert 상태
  * Recovery Log
  * Telegram Notification
  * Dashboard 반영 여부

  * [ ] Remote Adapter 구현

  목적:

  * AWS App / DB 대상 원격 Recovery 지원

  대상:

  * BankAppDown
  * PostgresDown
  * PostgresExporterDown

  검토:

  * SSH 기반 실행
  * 인증 정보 관리 방식
  * Verify 연계 방식

  범위 제외:

  * Failover
  * Replica Promote
  * Auto Scaling 제어

* [ ] Security Alert Metric 이름 확정

  * Login Failure Metric
  * Rate Limit Metric

* [ ] PostgresDown / PostgresExporterDown Recovery Policy 활성화

  확인 필요:

  * DB container name
  * PostgreSQL Exporter container name
  * 원격 실행 방식(Remote Adapter)

  Verify:

  * PostgresDown → pg_isready
  * PostgresExporterDown → metrics endpoint 또는 Prometheus up

  제외:

  * Replica Promote
  * Failover
  * DB 연결 정보 전환

  필요 작업:

  * Recovery Policy 값 확정
  * 통합 테스트

### 개선사항 (Low)

* [ ] Monitoring Component Health Check 강화

  대상:

  * Prometheus
  * Alertmanager
  * Grafana
  * Recovery Controller

  검토:

  * Docker Health Check
  * Host-level Watchdog
  * Monitoring 계층 Self-Healing 보완

* [ ] docker inspect 기반 조회 리팩토링

  * 출처: PR #10 Review

* [ ] docker.sock 권한 제한

  * docker-socket-proxy 검토
  * 권한 최소화 검토

* [ ] CloudWatch Alarm Telegram 알림 연동

  * CloudWatch Alarm → SNS → Lambda → Telegram
  * 우선순위: 후순위

### 완료

* [x] B Track App 정보 확인 후 BankAppDown 정책 값 확정

  * App container name
  * Health endpoint
  * Prometheus job_name

* [x] Recovery Retry 정책 구현

  * recovery_map.yaml의 retry 값 사용
  * 중간 실패는 recovery.log 기록
  * 최종 실패는 critical.log 기록
  * 최종 실패 시 Recovery Failure Notification 호출

* [x] recovery_map.yaml 캐싱 적용 검토
* [x] recovery_map.yaml 로딩 예외 처리 개선
* [x] 표준 Python logging 적용 검토
* [x] Recovery Action 비동기 처리 검토
* [x] 운영 컴포넌트 Self-Monitoring 한계 검토
* [x] Recovery Lock / Cooldown 구현 및 강화

---

## Alert / Recovery Policy

### 우선순위

### 확인 필요

* [ ] Alert Inventory 최종 정리

  포함 항목:

  * Alert Name
  * Severity
  * Category
  * Auto Recovery 여부
  * Verify 방식
  * Notification 여부

* [ ] PostgresDown / PostgresExporterDown Recovery Policy 활성화

### 완료

* [x] maintenance Alert 정책 최종 반영

  * Alert 발생 → Telegram X
  * Recovery 성공 → Telegram X
  * Retry 3회 실패 → Telegram O

* [x] Recovery Failure 정책 정의

  * Verify 실패 처리
  * Escalation 기준 정리

* [x] YAML 파일 확장자 `.yaml` 통일

* [x] 운영 컴포넌트 Alert Rule 추가

  * PrometheusDown
  * AlertmanagerDown
  * GrafanaDown
  * NginxExporterDown

* [x] 운영 컴포넌트 Recovery Policy 추가

  * auto_recovery
  * notify=false
  * maintenance.log

* [x] Grafana datasource에 Loki 추가

* [x] Loki / Promtail 기반 로그 수집 구성

---

## Dashboard / History

### 우선순위

* [ ] Dashboard 데이터 소스 매핑 정리

  정리 대상:

  * Prometheus
  * CloudWatch
  * Loki

  포함 내용:

  * 수집 데이터
  * 활용 목적
  * Dashboard 패널 위치

* [ ] Dashboard 시나리오 매핑 정리

  * 로그인 공격
  * API Flooding
  * 트래픽 증가 / ASG
  * App 장애
  * DB 장애
  * 안전 배포

* [ ] Monitoring & Recovery Quick Guide 작성

  포함 내용:

  * Prometheus

  * Alertmanager

  * Telegram

  * Recovery Controller

  * Loki

  * Grafana

  * Auto Recovery vs Notify Only

  * CloudWatch vs Prometheus

  * Dashboard 섹션 설명

  * 주요 Alert 설명

### 후순위

* [ ] CloudWatch Alarm Dashboard 반영 범위 확정

  대상:

  * ALB5xxHigh
  * TargetGroupUnhealthy
  * TargetGroupUnhealthyGreen
  * ASGScaleOut

### 완료

* [x] Recovery 로그 조회 기반 구성

* [x] Dashboard Panel 구성

  * Security
  * Application
  * Infrastructure
  * Recovery

* [x] Dashboard Provisioning 구성 및 검증

* [x] Recovery Metrics 구성

  * recovery_attempt_total
  * recovery_success_total



----

* [x] BankAppDown Alert → Notification → Recovery 경로 검증

  확인:

  * Prometheus Alert 발생
  * Alertmanager Route 동작
  * Telegram Alert 수신
  * Recovery Controller 수신
  * Retry 동작
  * Recovery Failure Notification 수신

  확인된 이슈:

  * AWS App 대상 Remote Adapter 미구현
  * Verify 시점이 너무 빠름