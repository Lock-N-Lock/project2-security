# [E] 보안 시나리오·대응 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | E — 보안 시나리오·대응 |
| 담당 | 박정은 (main) / 이지윤 (sub) |
| 초안 | 신준한 (※ 담당자 검수 필요) |
| 디렉토리 | `security/`, `docker/fail2ban/`, `docker/nginx/` |
| 최종 수정 | 2026-06-22 |

> ⚠️ 이 문서는 실제 코드 기반 **초안**입니다. 트랙 담당자(박정은·이지윤) 검수 후, 발표는 담당자가 진행하세요.

---

## 1. 개요

공격과 방어 양면을 담당합니다. **Locust로 공격(로그인 brute force·이체 폭주)**을 재현하고, **Nginx rate limit(1차) + fail2ban(2차)**의 다층 방어로 탐지·차단합니다. 차단 이벤트는 Telegram 알림과 D 트랙 시각화로 연결됩니다. 이 **런타임 차단**이 DevSecOps 4중 잠금의 마지막 단계입니다.

---

## 2. 디렉토리·파일 구조

```
security/
├── EXPLAIN.md                 # 보안 모듈 개요
├── locust/                    # 공격 시뮬레이션
│   ├── login_attack.py        #   CSRF 획득 → 틀린 비번 brute force (401 유발)
│   ├── flood_attack.py        #   API 폭주 (rate limit 유발)
│   └── normal_user.py         #   정상 사용자 baseline
├── policies/                  # incident-response·rate-limit-policy·test-checklist
└── scripts/                   # check-nginx-log.sh·test-rate-limit.sh

docker/nginx/                  # 1차 방어 (rate limit)
├── rate-limit.conf            #   login 5r/m·transfer 3r/m·api 10r/s → 429
├── nginx.conf · log-format.conf
docker/fail2ban/               # 2차 방어 (iptables 차단)
├── jail.local                 #   nginx-login·nginx-rate-limit·nginx-scan
├── filters.d/                 #   각 jail의 로그 패턴
└── telegram-alert.sh          #   차단 시 알림
```

---

## 3. 핵심 동작 흐름

### 공격 시나리오 (Locust)

| 시나리오 | 대상 | 기법 | 기대 반응 |
|---|---|---|---|
| `login_attack` | `/login` | CSRF 토큰 획득 후 틀린 비번 반복 POST | 401 → fail2ban 차단 |
| `flood_attack` | API | `wait_time=0` 무지연 폭주 | 429 → fail2ban 차단 |
| `normal_user` | 전체 | 정상 트래픽 | 정상(baseline 비교용) |

### 다층 방어

**1차 — Nginx rate limit** (`rate-limit.conf`, 초과 시 429)

| zone | 한도 |
|---|---|
| login_limit | 5 req/min |
| transfer_limit | 3 req/min |
| api_limit | 10 req/s |

**2차 — fail2ban** (로그 패턴 매칭 → iptables 차단)

| jail | maxretry / findtime | bantime | 대상 |
|---|---|---|---|
| nginx-login | 5 / 300s | 1h | 로그인 실패 |
| nginx-rate-limit | 20 / 60s | 30m | 429 폭주 |
| nginx-scan | 10 / 300s | 24h | 스캔성 요청 |

### 탐지 → 차단 → 알림 흐름

```
공격(Locust) → Nginx(rate limit 429 / [SECURITY] 로그)
            → fail2ban filter 매칭 → iptables 차단(ban)
            → telegram-alert.sh 알림 + D 트랙 시각화
```

---

## 4. 다른 트랙과의 인터페이스 (필수)

**내가 받는 것 (입력)**

| 어디서 | 무엇을 |
|--------|--------|
| B 트랙 | 공격 대상 엔드포인트(`/login`·`/transfer`), `[SECURITY]` 로그·`login_failed_total` |
| A 트랙 | 배포 환경(App EC2), `service_domain`(공격 타깃 URL) |
| C 트랙 | `set-fail2ban.sh`로 fail2ban 배포 |

**내가 내보내는 것 (출력)**

| 어디로 | 무엇을 |
|--------|--------|
| D 트랙 | 공격 트래픽·차단 이벤트(메트릭·로그·타임라인) |
| 운영 | iptables 차단(ban) + Telegram 알림 |

---

## 5. 실행·테스트 방법

```bash
# 공격 재현 (proj-mgmt 또는 별도 호스트)
locust -f security/locust/login_attack.py --host http://<service_domain>
locust -f security/locust/flood_attack.py --host http://<service_domain>

# rate limit 동작 확인
bash security/scripts/test-rate-limit.sh
bash security/scripts/check-nginx-log.sh        # 429·[SECURITY] 로그 확인

# fail2ban 상태 (App EC2)
sudo fail2ban-client status nginx-login
```

검증 포인트: 공격 → 429/401 → `fail2ban-client status`에 ban IP 등록 → Telegram 알림 → Grafana 타임라인.

---

## 6. 트러블슈팅 / 알려진 이슈

- **fail2ban은 로그 기반** → Nginx `log-format.conf`가 바뀌면 `filters.d`의 정규식도 같이 수정 필요.
- **rate limit 429 vs fail2ban ban 구분**: 429는 일시 거절(nginx), ban은 iptables 차단(fail2ban). 둘의 findtime/maxretry 튜닝은 `security/policies/rate-limit-policy.md` 참조.
- **차단 IP 해제**: `sudo fail2ban-client set <jail> unbanip <IP>` (데모 reset 시).
- **공격 호스트 자기 차단 주의**: 같은 IP로 공격·관리 동시 시 SSH까지 막힐 수 있음 → 관리 IP는 화이트리스트 검토.

---

## 7. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-06-22 | 초안(실제 코드 기반): Locust 3종·Nginx rate limit·fail2ban 3 jail·탐지→차단→알림·인터페이스 | 신준한 |