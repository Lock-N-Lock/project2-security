# Security Module Overview

## 목적

본 디렉토리는 프로젝트의 보안 기능 및 보안 검증 기능을 관리하기 위한 영역이다.

프로젝트는 금융 서비스 기반의 컨테이너 환경을 대상으로 하며, 공격 탐지 → 알림 → 대응 → 검증 흐름을 구현하는 것을 목표로 한다.

본 디렉토리에는 Nginx 기반 보안 정책, Fail2ban 차단 정책, 공격 시뮬레이션 도구(Locust), 보안 정책 문서 및 검증 자료가 포함된다.

---

# 디렉토리 구조

```text
security/
├── nginx/
├── fail2ban/
├── locust/
├── policies/
└── docs/
```

---

# nginx/
Nginx Reverse Proxy 및 요청 제어 정책을 관리한다.

주요 역할
* Reverse Proxy
* Rate Limit
* Access Log 생성
* Fail2ban 연계 로그 제공
* FastAPI 요청 전달

예정 파일

```text
nginx/
├── nginx.conf
├── rate-limit.conf
├── log-format.conf
└── README.md
```

---

# fail2ban/
로그인 공격 및 반복 요청 공격에 대한 자동 차단 정책을 관리한다.

주요 역할
* 로그인 실패 탐지
* 반복 요청 탐지
* IP 자동 차단
* 차단 이력 기록

예정 파일

```text
fail2ban/
├── jail.local
└── filters/
    └── nginx-login.conf
```

---

# locust/
공격 및 부하 테스트 시나리오를 관리한다.

주요 역할
* 정상 사용자 트래픽 생성
* 로그인 공격 시뮬레이션
* API Flooding 시뮬레이션
* Auto Scaling 검증
* Rate Limit 검증

예정 파일

```text
locust/
├── normal_user.py
├── login_attack.py
├── flood_attack.py
└── README.md
```

---

# policies/

보안 정책 문서를 관리한다.

주요 역할

* Rate Limit 기준 정의
* IP 차단 기준 정의
* 로그 보관 기준 정의
* 보안 대응 절차 정의
* 예외 처리 기준 정의

예정 파일

```text
policies/
├── security-policy.md
├── rate-limit-policy.md
├── incident-response.md
└── test-checklist.md
```

---

# docs/

보안 검증 결과 및 테스트 자료를 저장한다.

주요 역할

* 테스트 결과 보관
* 공격 시나리오 결과 정리
* 스크린샷 저장
* 발표 자료 연계

예정 구조

```text
docs/
├── screenshots/
├── reports/
└── test-results/
```

---

# 보안 흐름

```text
사용자 요청
↓
ALB + ACM
↓
Nginx
↓
FastAPI
↓
PostgreSQL

공격 발생
↓
Nginx Access Log
↓
Fail2ban 탐지
↓
IP 차단

또는

Locust 공격
↓
Rate Limit 동작
↓
429 반환
↓
Prometheus 수집
↓
Grafana 시각화
↓
Alertmanager 알림
```

---

# 본 디렉토리에서 관리하는 보안 기능
1. Nginx Reverse Proxy
2. Nginx Rate Limit
3. Access Log 포맷 관리
4. Fail2ban IP 차단 정책
5. Locust 기반 공격 시뮬레이션
6. 보안 정책 문서
7. 보안 검증 결과 문서

# 프로젝트 전체와 연계되는 보안 기능
1. HTTPS 통신 (ALB + ACM)
2. Prometheus/Grafana 모니터링
3. Alertmanager 알림
4. CloudWatch 인프라 감시
5. Bandit 코드 취약점 검사
6. Trivy 이미지 취약점 검사
7. ZAP 웹 취약점 검사
8. Blue-Green 배포 및 Rollback
