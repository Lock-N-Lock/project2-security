security/policies/rate-limit-policy.md
# Rate Limit Policy

> [!IMPORTANT]
> 본 정책은 Brute Force 공격 및 API Flooding 공격으로부터 애플리케이션을 보호하기 위해 Nginx Rate Limit 기준을 정의한다.

---

## 정책 목적

### 보안 목표

* 비정상 로그인 시도 제한
* API Flooding 공격 완화
* 애플리케이션 자원 보호
* 정상 사용자 서비스 가용성 보장

### 적용 대상

* Nginx Reverse Proxy
* FastAPI Application
* 금융 서비스 API

---

## 로그인 API 보호 정책

> [!WARNING]
> 로그인 API는 계정 탈취 공격의 주요 대상이므로 강한 요청 제한 정책을 적용한다.

### 대상 Endpoint

`/login`

### 설정

| 항목         | 값         |
| ---------- | --------- |
| Rate Limit | 5 req/sec |
| Burst      | 5         |
| 초과 응답      | HTTP 429  |

### 적용 목적

* Brute Force 공격 방어
* 비밀번호 추측 공격 차단
* 계정 탈취 시도 제한

### 동작 흐름

```text
사용자 요청
↓
Nginx
↓
Rate Limit 검사
↓
허용 → FastAPI 전달

또는

↓
HTTP 429 반환
↓
FastAPI 미전달
```

---

## 이체 API 보호 정책

> [!CAUTION]
> 금융 거래 기능은 서비스 내 가장 민감한 기능으로 간주한다.

### 대상 Endpoint

`/transfer`

### 설정

| 항목         | 값         |
| ---------- | --------- |
| Rate Limit | 3 req/sec |
| Burst      | 3         |
| 초과 응답      | HTTP 429  |

### 적용 목적

* 비정상 대량 이체 방지
* 자동화 공격 최소화
* 금융 거래 보호

### 동작 흐름

```text
사용자 요청
↓
Nginx
↓
Rate Limit 검사
↓
허용 → FastAPI 전달

또는

↓
HTTP 429 반환
```

---

## 일반 조회 API 보호 정책

### 대상 Endpoint

`/api/*`

### 설정

| 항목         | 값          |
| ---------- | ---------- |
| Rate Limit | 10 req/sec |
| Burst      | 20         |
| 초과 응답      | HTTP 429   |

### 적용 목적

* 잔액 조회 대응
* 거래내역 조회 대응
* 정상 사용자 사용성 보장

---

## Burst 정책

> [!TIP]
> Burst는 순간적으로 몰리는 요청을 임시 허용하는 버퍼(Buffer) 역할을 수행한다.

### 예시

로그인 API 설정

```nginx
limit_req zone=login_limit burst=5 nodelay;
```

### 동작 방식

```text
5 req/sec 허용
+
추가 5개 요청 임시 허용
=
총 10개 요청 허용
```

### 적용 이유

* 브라우저 새로고침
* 모바일 네트워크 재전송
* 일시적 트래픽 증가

---

## 차단 응답 정책

### 응답 코드

```http
HTTP/1.1 429 Too Many Requests
```

### 의미

요청 수가 허용 기준을 초과했음을 의미한다.

### 특징

* FastAPI까지 요청 미전달
* 애플리케이션 자원 보호
* 로그 기록 수행

---

## 연계 보안 정책

| 계층              | 보안 기능                |
| --------------- | -------------------- |
| Network         | Security Group       |
| Edge            | Cloudflare           |
| Reverse Proxy   | Nginx                |
| Request Control | Rate Limit           |
| Host Security   | Fail2ban             |
| Monitoring      | Prometheus / Grafana |
| Alert           | Alertmanager         |

---

## 보안 대응 흐름

```text
사용자 요청
↓
Cloudflare
↓
ALB + ACM
↓
Nginx Rate Limit
↓
허용 → FastAPI

또는

↓
HTTP 429 반환
↓
Access Log 기록
↓
Fail2ban 탐지
↓
IP 차단
```

> [!IMPORTANT]
> Nginx Rate Limit은 요청(Request)을 차단하며, Fail2ban은 공격 IP 자체를 차단한다.
