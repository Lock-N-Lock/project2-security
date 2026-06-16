# Security Test Checklist

> [!IMPORTANT]
> 본 체크리스트는 보안 기능 구현 및 시연 전 검증 항목을 정의한다.

---

## Nginx Reverse Proxy

### 설정 검증

* [ ] Nginx 컨테이너 정상 실행
* [ ] FastAPI Reverse Proxy 동작
* [ ] `/health` 정상 응답 확인
* [ ] Security Header 적용 확인

### 로그 검증

* [ ] JSON Access Log 생성
* [ ] request_time 기록
* [ ] User-Agent 기록
* [ ] Client IP 기록

---

## Nginx Rate Limit

### 로그인 API

* [ ] `/login` Rate Limit 동작
* [ ] HTTP 429 반환 확인
* [ ] FastAPI 요청 차단 확인

### 이체 API

* [ ] `/transfer` Rate Limit 동작
* [ ] HTTP 429 반환 확인

### 일반 API

* [ ] `/api/*` Rate Limit 동작
* [ ] Burst 정책 정상 동작

---

## Fail2ban

### 로그인 공격 차단

* [ ] HTTP 401 탐지
* [ ] Fail2ban 규칙 매칭
* [ ] 공격 IP 차단

### Flooding 공격 차단

* [ ] HTTP 429 탐지
* [ ] Fail2ban 규칙 매칭
* [ ] 공격 IP 차단

---

## Locust Attack Simulation

### Login Attack

* [ ] Locust 실행
* [ ] HTTP 401 증가 확인
* [ ] HTTP 429 증가 확인

### Flood Attack

* [ ] API Flooding 발생
* [ ] Rate Limit 동작 확인

---

## Monitoring

### Grafana

* [ ] 공격 로그 수집
* [ ] HTTP 401 시각화
* [ ] HTTP 429 시각화

### Alertmanager

* [ ] 공격 알림 수신
* [ ] 장애 알림 수신

---

## Deployment

### Docker

* [ ] Docker Build 성공
* [ ] Docker Compose 실행 성공

### Health Check

* [ ] Application Health Check 성공
* [ ] Nginx Health Check 성공

### Blue-Green

* [ ] Green 배포 성공
* [ ] Health Check 성공
* [ ] Traffic 전환 성공

---

## 최종 결과

* [ ] 로그인 공격 차단 검증 완료
* [ ] API Flooding 차단 검증 완료
* [ ] 모니터링 검증 완료
* [ ] 알림 검증 완료
* [ ] 무중단 배포 검증 완료