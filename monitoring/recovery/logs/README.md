# Recovery / Event Logs

이 디렉터리는 Alert / Recovery / Event 이력을 저장하기 위한 로그 경로이다.

## Log Files

| File | Purpose |
|---|---|
| recovery.log | 사용자 서비스 장애 복구 이력 |
| maintenance.log | Prometheus, Alertmanager, Grafana, Exporter 등 운영 컴포넌트 자동복구 이력 |
| event.log | 보안 이벤트 및 CloudWatch 기반 인프라 이벤트 |
| critical.log | DB 장애, 복구 실패, 수동 개입 필요 이벤트 |

## Event Sources

| Source | Example |
|---|---|
| Prometheus Alert | BankAppDown, GrafanaDown, NginxExporterDown |
| Recovery Result | Recovery Success / Failed |
| CloudWatch Alarm | ALB5xxHigh, TargetGroupUnhealthy, ASGScaleOut |
| Security Event | HighLoginFailureRate, RateLimitTriggered |

## Future Usage

- Grafana Dashboard 연동
- Alert History / Event Timeline 구성
- Recovery Count 계산
- Recovery Success Rate 계산
- MTTR 계산
- 반복 장애 분석
- ASG ScaleOut 패턴 확인