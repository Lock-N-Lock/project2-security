# [D] 모니터링·알림·복구 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | D — 모니터링·알림·복구 |
| 담당 | 이지윤 (main) / 박정은 (sub) |
| 초안 | 신준한 (※ 담당자 검수 필요) |
| 디렉토리 | `monitoring/` |
| 최종 수정 | 2026-06-22 |

> ⚠️ 이 문서는 실제 코드 기반 **초안**입니다. 트랙 담당자(이지윤·박정은) 검수 후, 발표는 담당자가 진행하세요.

---

## 1. 개요

proj-mgmt(온프레)에서 실행되는 관측·대응 스택입니다. AWS·앱·컨테이너·DB의 메트릭/로그를 수집·시각화하고, 보안 이벤트를 **탐지 → 알림(Telegram) → 자동 복구(verify)** 흐름으로 연결합니다.
메트릭 수집은 SG가 아닌 **Tailscale 노드망(100.x)**으로 이뤄지며, App ASG의 동적 노드는 `tailscale-sd`가 자동 발견합니다.

---

## 2. 디렉토리·파일 구조

```
monitoring/
├── docker-compose.monitoring.yaml  # 스택 11개 컨테이너
├── bootstrap_monitoring.sh         # 오케스트레이션(AWS 조회→.env.generated→템플릿 치환→배포)
├── Makefile                        # bootstrap·up·down·destroy·teardown
├── prometheus/   (prometheus.yaml + rules/alert_rules.yaml)
├── alertmanager/ (alertmanager.yaml)
├── grafana/      (dashboards/ + provisioning/ datasources: prometheus·loki·cloudwatch)
├── loki/ + promtail/               # 로그 집계·수집
├── telegram-notifier/              # Alertmanager webhook → Telegram
├── recovery/                       # 자동 복구 컨트롤러 (정책·verify·actions)
├── tailscale-sd/                   # App ASG 동적 노드 발견(http_sd)
├── lambda/cloudwatch-telegram-notifier/  # CloudWatch→SNS→Lambda→Telegram + teardown
├── scripts/      (nginx_log_metrics.sh·security_event_timeline.sh·setup_aws_nginx_log_backup.sh)
└── security-center/                # 보안 이벤트 요약 페이지
```

### 스택 컨테이너 (docker-compose)

| 컨테이너 | 이미지 | 역할 |
|---|---|---|
| prometheus | prom/prometheus | 메트릭 수집·알람 평가 |
| alertmanager | prom/alertmanager | 알림 라우팅 |
| grafana | grafana/grafana | 시각화 (Prometheus·Loki·CloudWatch) |
| loki / promtail | grafana/loki·promtail | 로그 집계·수집 |
| nginx / nginx-exporter | nginx·exporter | 모니터링 프록시·nginx 메트릭 |
| blackbox-exporter | prom/blackbox | 외부 endpoint probe |
| telegram-notifier | (빌드) | Alertmanager → Telegram |
| recovery | (빌드) | 정책 기반 자동 복구 |
| tailscale-sd | (빌드) | App 노드 http_sd |

---

## 3. 핵심 동작 흐름

### 수집 → 시각화
- **메트릭**: Prometheus가 Tailscale 노드(App 9100/9113, DB 9100/9187, nginx 로그 9105)를 scrape. App ASG는 `tailscale-sd`(http_sd)로 동적 발견.
- **로그**: Promtail → Loki → Grafana.
- **probe**: blackbox-exporter가 서비스 endpoint 헬스 probe.

### 알림 (이중 경로)
1. **AWS 인프라**: CloudWatch 알람 → SNS → **Lambda** → Telegram (`lambda/cloudwatch-telegram-notifier`)
2. **앱·컨테이너**: Prometheus rules → Alertmanager → **telegram-notifier** → Telegram

### 자동 복구 (`recovery/`)
- `recovery_map.yaml` 정책: `mode`(auto_recovery / notify_only), `category`(user_service / maintenance / security)
- 흐름: 탐지 → 정책 매칭(loader) → 액션 실행(runner: `aws_app_restart.sh`·`docker_restart.sh`) → **verify(http)** → 복구 로그
- 카테고리별: user_service=알림+복구, maintenance=복구만, security=알림만(복구 X)

### bootstrap (`make bootstrap`)
`.env` 확인 → 필수 도구 → App/Monitoring Tailscale IP 조회 → AWS 리소스 조회 → `.env.generated` 생성 → `prometheus.yaml` scrape job·Grafana/Security Center 템플릿 치환 → CloudWatch Telegram Lambda 배포 → docker compose up.

---

## 4. 다른 트랙과의 인터페이스 (필수)

**내가 받는 것 (입력)**

| 어디서 | 무엇을 |
|--------|--------|
| A 트랙 | `grafana_cw_access_key`/`secret`(CloudWatch datasource), `alerts_sns_arn`, `db_tailscale_ip` |
| A 트랙 | App/DB가 Tailscale 노드(tag:app)로 가입 → scrape 경로 |
| B 트랙 | `/metrics`(login_failed_total·transfer_requests_total) + `[SECURITY]` 로그 |
| E 트랙 | 보안 이벤트(공격 트래픽) → 탐지·시각화 대상 |

**내가 내보내는 것 (출력)**

| 어디로 | 무엇을 |
|--------|--------|
| 전체 | Grafana 대시보드·Telegram 알림 |
| 운영 | 자동 복구(앱 재시작) + 복구 로그 |
| E 트랙 | 보안 이벤트 타임라인(security-center) |

---

## 5. 실행·테스트 방법

```bash
# 권장: 프로젝트 루트에서 (:9105 nginx 로그까지 포함)
make monitoring-service        # = monitoring-bootstrap + monitoring-nginx-logs

# monitoring 디렉토리 직접 (운영)
cd monitoring
make bootstrap                 # 최초 구성 (※ :9105는 별도 — 루트 명령 권장)
make up / down / restart / logs / ps

# 정리
make destroy                   # 컨테이너·볼륨
make teardown                  # AWS 리소스(Lambda/IAM/Alarm) dry-run 확인
```

검증:
```bash
curl -s localhost:9105/nginx_log_metrics.prom | head   # nginx 로그 메트릭
# Grafana(3000)·Prometheus(9090) Targets UP, Alertmanager(9093)
```

---

## 6. 트러블슈팅 / 알려진 이슈

- **`:9105`는 `bootstrap`에 미포함** → 루트 `make monitoring-service`/`full-service` 사용(디렉토리 직접 `make bootstrap`만 하면 빈 패널 재발).
- **`prometheus.yaml`·dashboard json이 실행마다 런타임 IP 주입으로 git-dirty** → 커밋 금지(`git restore`). 근본 해결은 `.j2` 템플릿 분리(후속 과제).
- **AWS 리소스 정리**: `bootstrap`이 만든 Lambda/IAM/CW알람은 `make teardown-force`로 정리(루트 `make destroy`가 자동 호출). SNS topic은 Terraform 소관.
- **PostgresDown(복구) 정책 미정**: `monitoring/recovery/config/recovery_map.yaml`에 추후 결정 표기.

---

## 7. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-06-22 | 초안(실제 코드 기반): 11컨테이너·이중 알림 경로·recovery 정책·Tailscale SD·bootstrap 흐름·인터페이스 | 신준한 |