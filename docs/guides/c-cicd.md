# [C] CI/CD·DevSecOps 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | C — CI/CD·DevSecOps |
| 담당 | 임종원 (main) / 신준한 (sub) |
| 디렉토리 | `.github/workflows/`, `scripts/` |
| 최종 수정 | 2026-06-22 |

---

## 1. 개요

코드 push부터 인프라 plan·보안 검사·이미지 빌드·배포까지 GitHub Actions로 자동화합니다.
핵심은 **DevSecOps 4중 잠금** — 취약한 코드/이미지가 운영에 반영되지 않도록 SAST·이미지 스캔·DAST·런타임 차단을 파이프라인에 배치합니다. (Blue-Green 무중단 전환은 폐기하고, 보안 스캔 게이트로 차별화)

---

## 2. 디렉토리·파일 구조

```
.github/workflows/
├── plan.yml      # [push 자동] terraform plan + Bandit(SAST) + 이미지 빌드 + Trivy + Docker Hub push
├── deploy.yml    # [수동 workflow_dispatch] terraform apply + ZAP(DAST 관측)
└── destroy.yml   # [수동 workflow_dispatch] terraform destroy
scripts/
├── build-push-image.sh  # 멀티아치 이미지 빌드·푸시 (make build-push 가 호출)
├── deploy-app.sh        # App EC2에 컨테이너 배포 (bootstrap 이미지 + docker run)
└── set-fail2ban.sh      # 앱 인스턴스 fail2ban 설정 주입 (런타임 차단)
```

---

## 3. 핵심 동작 흐름

### CI — `plan.yml` (push 시 자동)
1. `terraform init` & `terraform plan` — 인프라 변경 미리보기
2. **Bandit** — `bandit -r ./app -l` (Python SAST)
3. `docker build` — `lock-app` 이미지 빌드
4. **Trivy** — 빌드된 이미지 취약점 스캔
5. `docker push` — `lock-app:${run_number}` + `:latest` → Docker Hub

### CD — `deploy.yml` (수동 실행)
1. `terraform apply --auto-approve`
2. `service_domain` / `alb_dns_name` output 확인
3. **OWASP ZAP** baseline — 배포된 서비스 DAST (현재 관측 단계, 게이트 아님)

### 삭제 — `destroy.yml` (수동 실행)
1. `terraform destroy --auto-approve`

### DevSecOps 4중 잠금

| 단계 | 도구 | 위치 | 역할 |
|------|------|------|------|
| SAST | Bandit | plan.yml | Python(app) 코드 취약점 |
| 이미지 | Trivy | plan.yml | 컨테이너 이미지·패키지 취약점 |
| DAST | OWASP ZAP | deploy.yml | 배포 웹 취약점 (관측) |
| 런타임 | fail2ban + Nginx rate limit | set-fail2ban.sh + nginx | 로그인 공격·API flooding 차단 |

---

## 4. 다른 트랙과의 인터페이스 (필수)

**내가 받는 것 (입력)**

| 어디서 | 무엇을 | 형식·경로 |
|--------|--------|-----------|
| A 트랙 | terraform 코드 / outputs(`alb_dns_name`·`service_domain`) | `infra/terraform/`, `terraform output` |
| B 트랙 | app 코드 + Dockerfile | `docker/app/` (이미지 빌드 대상) |
| GitHub Secrets | AWS·DockerHub·Tailscale·CF 키, `DB_PASSWORD` | Repo/Env secrets |

**내가 내보내는 것 (출력)**

| 어디로 | 무엇을 | 형식·경로 |
|--------|--------|-----------|
| 배포 서버 / B | `lock-app` 이미지 | Docker Hub `:${run_number}`·`:latest` |
| D 트랙 | 배포된 서비스(모니터링 대상) | ALB DNS |
| E 트랙 | 배포된 서비스(공격·검증 대상) | `service_domain` |

> Secrets는 워크플로의 `terraform init`/`apply`에 `TF_VAR_*`로 주입됩니다(예: `TF_VAR_db_password = secrets.DB_PASSWORD`).

---

## 5. 실행·테스트 방법

```bash
# CI: push 하면 plan.yml 자동 실행 (Actions 탭에서 확인)
git push

# CD/Destroy: GitHub → Actions → 해당 워크플로 → "Run workflow" (수동)

# 로컬에서 이미지 빌드·푸시만 (CI와 동일 산출물)
make build-push            # scripts/build-push-image.sh
make service               # 빌드·푸시 + 인프라 + DB 통합
```

---

## 6. 트러블슈팅 / 알려진 이슈

- **plan.yml이 `on: push`만** (PR 트리거 아님): PR 단위 게이트가 아직 미적용 → `on: pull_request` 추가 검토.
- **ZAP은 관측 단계**(`fail_action:false`): Critical/High 발견 시 배포 차단 게이트로 승격 검토.
- **bootstrap·nginx 이미지는 CI 자동 재빌드 부재**: 현재 `make build-push-bootstrap` 등 수동. lock-app만 CI가 빌드/푸시.
- **Blue-Green 전환 자동화 폐기**: green ASG는 desired=0 예비로 유지하되, 무중단 전환 스크립트는 제거하고 4중 스캔 게이트로 차별화.
- **죽은 변수 `app_image` 정리 완료**: plan/deploy/destroy에서 미사용 주입 제거(PR #63·#64).

---

## 7. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-06-22 | 초안 작성: plan/deploy/destroy 워크플로·4중 잠금·인터페이스·알려진 이슈 정리 | 신준한 |