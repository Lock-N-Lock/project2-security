# [B] 앱서비스·컨테이너 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | B — 앱서비스·컨테이너 |
| 담당 | 최상우 (main) / 임종원 (sub) |
| 초안 | 신준한 (※ 담당자 검수 필요) |
| 디렉토리 | `docker/app/` |
| 최종 수정 | 2026-06-22 |

> ⚠️ 이 문서는 실제 코드 기반 **초안**입니다. 트랙 담당자(최상우·임종원) 검수 후, 발표는 담당자가 진행하세요.

---

## 1. 개요

FastAPI 기반 금융 데모 앱(**LockBank**)입니다. 로그인·잔액조회·이체를 제공하며, 보안 이벤트(로그인 실패·이체 폭주)를 **Prometheus 메트릭**과 **`[SECURITY]` 로그**로 노출해 D(모니터링)·E(보안 시나리오) 트랙의 탐지 대상이 됩니다.
강사 가이드대로 공식 `python:3.11-slim` 이미지를 pull → Dockerfile로 빌드 → Docker Hub push 합니다(k8s 미사용).

---

## 2. 디렉토리·파일 구조

```
docker/app/
├── Dockerfile          # python:3.11-slim, uvicorn :8080, GITHUB_ACTOR ARG
├── main.py             # FastAPI 앱 (엔드포인트·DB풀·보안·metrics)
├── requirements.txt    # fastapi·uvicorn·psycopg2·bcrypt·prometheus_client·itsdangerous·jinja2
└── templates/          # Jinja2 — login.html · dashboard.html · transfer.html
```

---

## 3. 핵심 동작 흐름

### 엔드포인트

| 메서드·경로 | 인증 | 기능 | DB |
|---|---|---|---|
| GET `/` | — | 세션 있으면 `/dashboard`, 없으면 `/login` | — |
| GET·POST `/login` | — | 로그인 | replica(읽기) |
| GET `/logout` | — | 세션 쿠키 제거 | — |
| GET `/dashboard` | 세션 | 잔액·거래내역 조회 | replica(읽기) |
| GET·POST `/transfer` | 세션 | 이체 | main(쓰기) |
| GET `/metrics` | — | Prometheus 노출 | — |

### Main / Replica 풀 분리 (읽기·쓰기 분리)

- `main_pool` (`DB_HOST_MAIN`) — **쓰기**: 이체(`transactions` insert, `balance` update)
- `replica_pool` (`DB_HOST_REPLICA`) — **읽기**: 로그인 조회·dashboard
- `ThreadedConnectionPool(1, 10)`, `lifespan`에서 초기화/종료
- DB IP는 env 주입 (배포 시 A 트랙 outputs → deploy-app.sh)

### 보안 기능 (E 트랙 탐지 연계)

- **CSRF**: 폼마다 토큰 발급·검증, 실패 시 `[SECURITY] CSRF_FAILURE` 로그 + 403
- **bcrypt + DUMMY_HASH**: 없는 계정도 더미 해시를 비교해 **username enumeration·timing attack 방지**
- **세션**: `URLSafeTimedSerializer`(SECRET_KEY 서명, 24h 만료)
- **`[SECURITY]` 로그**: Nginx 로그 → fail2ban이 이 패턴으로 차단(E 트랙)

### Prometheus 메트릭

| 메트릭 | 타입 | 의미 |
|---|---|---|
| `login_failed_total` | Counter | 로그인 실패 누적 → **로그인 공격 탐지** |
| `transfer_requests_total` | Counter | 이체 요청 누적 → **이체 폭주 탐지** |

> `/metrics`(:8080)로 노출 → D 트랙 Prometheus가 수집.

---

## 4. 다른 트랙과의 인터페이스 (필수)

**내가 받는 것 (입력)**

| 어디서 | 무엇을 |
|--------|--------|
| A 트랙 | DB 접속 정보 env(`DB_HOST_MAIN`·`DB_HOST_REPLICA`·`DB_USER`·`DB_PASSWORD`·`DB_NAME`), `SECRET_KEY` |
| A 트랙 | 배포 환경(App EC2, user_data가 bootstrap 이미지로 pull·run) |
| A 트랙 | DB 스키마 `infra/ansible/init.sql` (users·transactions) |
| C 트랙 | 이미지 빌드·푸시(CI plan.yml), 배포 |

**내가 내보내는 것 (출력)**

| 어디로 | 무엇을 |
|--------|--------|
| D 트랙 | `/metrics`(:8080) `login_failed_total`·`transfer_requests_total` + `[SECURITY]` 로그 |
| E 트랙 | 공격 대상 엔드포인트(`/login`·`/transfer`) |
| (앞단) | Nginx(80) → FastAPI(8080) 프록시 |

> **DB 스키마**: `users(id·username·password·account_number·balance)`, `transactions(id·user_id·target_account·title·amount·created_at)`.

---

## 5. 실행·테스트 방법

```bash
# 로컬 빌드/실행
docker build -t lock-app docker/app
docker run -p 8080:8080 \
  -e DB_HOST_MAIN=<ip> -e DB_HOST_REPLICA=<ip> \
  -e DB_USER=<u> -e DB_PASSWORD=<p> -e DB_NAME=<db> -e SECRET_KEY=<key> \
  lock-app
curl localhost:8080/metrics            # login_failed_total 등 확인

# CI/배포 (C 트랙)
make build-push                        # Docker Hub push (lock-app)
```

---

## 6. 트러블슈팅 / 알려진 이슈

- **DB env 미주입 시 `127.0.0.1` 기본값** → 컨테이너 단독 실행 시 DB 연결 실패. 배포는 `deploy-app.sh`가 env 주입.
- **`SECRET_KEY` 기본값 `change-me-in-production`** → 운영 시 반드시 주입(세션 위조 방지).
- **포트 주의**: 앱 `8080`, Nginx `80`. metrics는 `8080/metrics`.
- **`get_server_info()`의 EC2 메타데이터 조회는 주석 처리** → 현재 hostname 반환(IMDS 호출 비활성).

---

## 7. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-06-22 | 초안(실제 코드 기반): 엔드포인트·main/replica 분리·보안(CSRF·bcrypt·세션)·metrics·인터페이스 | 신준한 |