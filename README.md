# 금융 서비스 기반 보안 이벤트 탐지 및 자동 대응 클라우드 인프라 구축

### 🗨️ 프로젝트 소개

> 
> 
> 
> 본 프로젝트는 AWS 기반 클라우드 환경에서 금융 서비스 형태의 데모 애플리케이션을 컨테이너로 배포하고, 로그인 실패 및 이체 요청 폭주와 같은 보안 이벤트를 실시간으로 탐지·시각화·알림·대응하는 운영 보안 자동화하는 DevSecOps 시스템을 구현하는 것을 목표로 함.
> 
> 단순한 웹 서비스 개발이 아니라, 클라우드 인프라 환경에서 서비스 운영 중 발생할 수 있는 이상 트래픽과 보안 이벤트를 감지하고, 자동 대응 및 복구 흐름까지 연결하는 데 중점을 둠.
> 

서비스 배포를 넘어, 보안 이벤트 발생 시 자동으로 탐지·대응·복구하는 클라우드 운영 보안 플랫폼을 구축함.

### 💠 팀명

- Lock & Lock

### 💠 팀원

- 신준한(팀장), 박정은, 이지윤, 임종원, 최상우

### 💠 역할 분담

`각 팀원의 역할과 책임`

- 신준한/박정은: AWS 구성, Terraform 코드 작성, Security Group 설계, Auto Scaling 연계 검토
- 최상우/임종원: FastAPI 금융 데모(로그인·조회·이체), PostgreSQL 연동, Prometheus Custom Metrics 제공, Dockerfile 작성 + ansible
- 임종원/신준한: GitHub Actions, Docker Hub/GHCR 연동, Blue-Green 배포 구조, SAST(Bandit) + Trivy + DAST(ZAP) + 워크플로 통합,
- 이지윤/박정은: Prometheus, Grafana, Alertmanager, Telegram 연동, Dashboard 구성, Alert Rule 작성
- 박정은/이지윤: Locust 부하 공격 시나리오, Nginx Rate Limit, fail2ban, 보안 이벤트 검증, 탐지→알림→대응 흐름 테스트 Health Check, 전환 및 Rollback 스크립트


# Lock & Lock — 금융 서비스 보안 자동 대응 시스템

악성 IP 자동 차단과 침입 시 환경 격리(Blue→Green 전환)를 통한 **보안**, 트래픽 부하에 따른 오토스케일링으로 달성하는 **비용·가용성**, 정책 기반 자동 대응과 상태 검증(verify)·복구 로그를 통한 **운영 안정성** — 이 세 가지를 핵심 가치로 하는 하이브리드(온프레미스↔AWS) 보안 대응 시스템입니다.

---

## 팀 & 트랙

| 트랙 | 영역 | main / sub | 디렉토리 |
|------|------|------------|----------|
| A | 인프라·IaC | 신준한 / 박정은 | `infra/terraform`, `infra/ansible` |
| B | 앱서비스·컨테이너 | 최상우 / 임종원 | `app/` |
| C | CI/CD·Blue-Green | 임종원 / 신준한 | `.github/workflows`, `scripts/` |
| D | 모니터링·알림·복구 | 이지윤 / 박정은 | `monitoring/` |
| E | 보안 시나리오·대응 | 박정은 / 이지윤 | `security/` |

---

## 🚀 시작하기 (초기 환경 세팅)

proj-mgmt(VMware, Rocky 8)에서 아래 세 스크립트를 순서대로 실행하면 됩니다.
**상세 절차·사전 준비물·트러블슈팅은 [docs/guides/setup-guide.md](./docs/guides/setup-guide.md) 를 참고하세요.**

```bash
cd ~/project2-security
chmod +x setup.sh check.sh bootstrap_tailscale.sh   # 최초 1회
bash setup.sh             # ① 도구 설치 + AWS 자격증명 + Docker Hub 로그인
./bootstrap_tailscale.sh  # ② Tailscale 연결 (+ VXLAN 준비)
make check                # ③ 환경 점검
```

| 스크립트 | 역할 |
|---|---|
| `setup.sh` | AWS CLI·Terraform·Ansible·Docker 설치 + AWS 자격증명·Docker Hub 등록 |
| `bootstrap_tailscale.sh` | Tailscale 하이브리드 연결 + VXLAN 오버레이 준비 |
| `check.sh` | 도구·자격증명·연결 상태 점검 |

> 세팅 완료 후 `make check`에서 `[6] VXLAN`만 ⚠️로 나오는 것은 정상입니다(AWS Bastion 생성 전). Bastion 생성 후 VXLAN 적용 절차도 [가이드](./docs/guides/setup-guide.md)에 있습니다.

---

## 인프라 배포 (Terraform)

초기 환경 세팅 완료 후, AWS 인프라를 프로비저닝합니다.

```bash
cd infra/terraform
make init                 # terraform init
make plan                 # 변경 미리보기
make apply                # 인프라 생성 (+ Ansible 자동 구성)
make output               # Bastion·EC2 IP 등 출력 확인
make destroy              # 실습 후 리소스 삭제 (비용 절감)
```

> ⚠️ 개인 AWS 계정 사용 → 실습 후 반드시 `make destroy`. destroy 전 `make backup`으로 DB dump를 S3에 보존합니다.

---

## 디렉토리 구조

```
project2-security/
├── README.md             # 본 문서
├── setup.sh              # 초기 환경 설치 스크립트
├── check.sh              # 환경 점검 스크립트
├── bootstrap_tailscale.sh# Tailscale + VXLAN 연결 스크립트
├── Makefile              # terraform·환경 명령어 단축
├── docs/                 # 설계서·다이어그램·가이드
│   ├── network-design.md # 네트워크 설계서 (CIDR·SG 매트릭스) — A 트랙 산출물
│   ├── guides/           # 트랙별 코드 동작 설명 + setup-guide.md
│   └── diagrams/         # 아키텍처 다이어그램
├── infra/
│   ├── terraform/        # A 트랙 — VPC·Subnet·EC2·SG (IaC)
│   └── ansible/          # A·B 트랙 — 구성관리
├── app/                  # B 트랙 — FastAPI·Dockerfile·DB 스키마
├── monitoring/           # D 트랙 — prometheus·grafana·alertmanager
├── security/             # E 트랙 — locust·rate limit·보안 정책
├── scripts/              # C 트랙 — deploy-bluegreen.sh 등 배포 스크립트
└── .github/workflows/    # C 트랙 — GitHub Actions (경로 고정)
```

> `.github/workflows/`는 GitHub Actions가 강제하는 고정 경로입니다. C 트랙의 워크플로 YAML은 반드시 이 위치에, 배포 스크립트는 `scripts/`에 둡니다.

---

## 브랜치 전략 & PR 흐름

```
feature/<트랙>-<주제>  →  dev (임종원 리뷰·머지)  →  main (신준한 최종 승인)  →  자동 배포
```

- **main**: 최종 운영 브랜치. CI/CD가 main push에 자동 배포.
- **dev**: 통합 개발 브랜치. 일상 PR 리뷰·머지 게이트.
- **feature/**: 각자 작업 브랜치. 보호 룰 미적용이라 자유롭게 commit/push 가능.

트랙 약자: `a`(인프라) `b`(앱) `c`(CI/CD) `d`(모니터링) `e`(보안)
예) `feature/a-vpc`, `feature/b-login-api`, `feature/d-grafana`

**적용된 보호 룰 (main·dev 공통)**: PR 필수 · 리뷰 승인 1명 이상 · 리뷰 코멘트 전부 resolve 필요 · 승인 후 새 커밋 시 재리뷰 · force push·브랜치 삭제 차단.

> PR 생성 시 base 브랜치를 **dev**로 둡니다(main 아님).

---

## 코드 가이드 문서 규칙

각 담당자는 본인 코드가 어떻게 동작하는지 설명하는 가이드를 `docs/guides/`에 작성합니다.

- **네이밍**: `<트랙소문자>-<영역>.md` (예: `a-infra-terraform.md`)
- **템플릿**: `docs/guides/_TEMPLATE.md`를 복사해 작성
- **필수 섹션**: "다른 트랙과의 인터페이스" — 내가 받는 입력 / 내가 내보내는 출력 명시

---

## 기술 스택

- 클라우드: AWS (VPC·EC2·ASG·CloudWatch·SG/NACL·ALB·Route53·ACM·S3)
- 하이브리드 연결: Tailscale(암호화 언더레이) + VXLAN(L2 오버레이)
- 컨테이너: Docker, Docker Swarm(overlay)
- 앱: FastAPI + PostgreSQL
- 리버스 프록시: Nginx
- IaC: Terraform, Ansible
- CI/CD: GitHub Actions, Docker Hub
- 모니터링: Prometheus, Grafana, Alertmanager / 알림: Telegram·Slack
- 부하·공격 시뮬레이션: Locust
- DevSecOps(4중 잠금): Bandit(SAST), Trivy(이미지), OWASP ZAP(DAST), fail2ban·Nginx rate limit(런타임)