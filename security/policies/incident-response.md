security/policies/incedent-response.md
# Incident Response Policy

> [!IMPORTANT]
> 본 문서는 보안 이벤트 발생 시 **탐지(Detection) → 알림(Alert) → 대응(Response) → 복구(Recovery)** 절차를 정의한다.

---

## 로그인 공격 (Brute Force Attack)

> [!WARNING]
> 반복적인 로그인 실패 요청이 발생할 경우 Fail2ban이 공격 IP를 자동 차단한다.

### 공격 시나리오

공격자가 `/login` API에 대해 반복적인 인증 시도를 수행하여 계정 탈취를 시도한다.

### 탐지

* Nginx Access Log 분석
* HTTP 401 응답 증가
* Fail2ban 로그인 공격 규칙 탐지
* Grafana Dashboard 확인

### 알림

* Alertmanager 알림 발송
* 운영자 Telegram 채널 통보

### 대응

* Fail2ban IP 자동 차단
* 공격 발생 시간 확인
* 공격 IP 확인 및 기록

### 복구

* 차단 이력 확인
* 정상 사용자 오탐 여부 검토
* 서비스 정상 동작 여부 확인

### 관련 시스템

| 구분            | 시스템              |
| ------------- | ---------------- |
| Reverse Proxy | Nginx            |
| 공격 탐지         | Fail2ban         |
| 로그 수집         | Nginx Access Log |
| 모니터링          | Grafana          |
| 알림            | Alertmanager     |

---

## API Flooding 공격

> [!CAUTION]
> 대량 요청으로 인한 서비스 자원 고갈을 방지하기 위해 Nginx Rate Limit 정책을 적용한다.

### 공격 시나리오

공격자가 API Endpoint에 대량 요청을 발생시켜 서비스 자원을 고갈시키고 정상 사용자의 요청을 방해한다.

### 탐지

* HTTP 429 응답 증가
* Nginx Rate Limit 동작
* Grafana 시각화
* CPU / Memory 사용량 증가

### 알림

* Alertmanager 알림 발송
* 운영자 Telegram 채널 통보

### 대응

* 공격 IP 확인
* Fail2ban 자동 차단
* 서버 리소스 상태 확인
* Rate Limit 정책 검토

### 복구

* 서비스 정상 여부 확인
* 공격 종료 여부 확인
* 리소스 사용량 정상화 확인

### 관련 시스템

| 구분            | 시스템                  |
| ------------- | -------------------- |
| Reverse Proxy | Nginx                |
| 요청 제한         | Nginx Rate Limit     |
| 공격 탐지         | Fail2ban             |
| 모니터링          | Prometheus / Grafana |
| 알림            | Alertmanager         |

---

## 애플리케이션 장애

> [!IMPORTANT]
> 장애 발생 시 서비스 중단 시간을 최소화하고 필요 시 Blue-Green 전환을 수행한다.

### 장애 시나리오

FastAPI 컨테이너 또는 애플리케이션 프로세스가 비정상 종료된다.

### 탐지

* Health Check 실패
* CloudWatch Alert 발생
* ALB Target Unhealthy 증가
* Grafana 대시보드 확인

### 알림

* Alertmanager 알림 발송
* 운영자 Telegram 채널 통보

### 대응

* 컨테이너 자동 재시작
* Docker 상태 확인
* Ansible 복구 수행
* 로그 분석

### 복구

* 서비스 정상 동작 확인
* Health Check 정상 복귀 확인
* 모니터링 지표 확인

### 최종 대응

> [!WARNING]
> 장애가 지속될 경우 Blue → Green 전환 또는 Rollback을 수행한다.

### 관련 시스템

| 구분     | 시스템                   |
| ------ | --------------------- |
| 컨테이너   | Docker                |
| 상태 확인  | Health Check          |
| 모니터링   | CloudWatch            |
| 자동화    | Ansible               |
| 무중단 배포 | Blue-Green Deployment |

---

## 보안 대응 흐름

```text
사용자 요청
↓
Cloudflare
↓
ALB + ACM
↓
Nginx
↓
FastAPI

공격 발생
↓
Nginx Access Log
↓
Fail2ban 탐지
↓
IP 차단
↓
Alertmanager 알림
↓
Grafana 시각화
```

> [!TIP]
> Nginx Rate Limit은 요청(Request)을 제한하며, Fail2ban은 공격 IP 자체를 차단한다.
