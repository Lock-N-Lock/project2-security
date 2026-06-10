# [A] 인프라·Terraform 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | A — 인프라·IaC |
| 담당 | 신준한 (main) / 박정은 (sub) |
| 디렉토리 | `infra/terraform/`, `infra/ansible/` |
| State | S3 backend (개인 버킷 + DynamoDB lock) |
| 최종 수정 | 2026-06-07 |

---

## 1. 개요

AWS 위에 프로젝트의 네트워크·컴퓨트·보안·관측 토대를 Terraform으로 프로비저닝합니다.
다른 모든 트랙(B 앱 / C CI·CD / D 모니터링 / E 보안)이 이 인프라 위에서 동작하므로, **A가 가장 먼저 떠야** 후속 작업이 가능합니다.

구성 요소 한눈에:

```
                          인터넷
                            │ 80/443
                       ┌────▼────┐
                       │   ALB   │  (TG: blue / green, /health)
                       └────┬────┘
        ┌───────────────────┼────────────────────┐
        │ (AZ-a)            │ 80                  │ (AZ-c)
   ┌────▼─────┐        ┌────▼─────┐          ┌────▼─────┐
   │ App ASG  │  …    │ App ASG  │   …      │ (확장분)  │   ← Blue(운영)/Green(예비)
   │  blue    │        │  blue    │          │          │
   └────┬─────┘        └────┬─────┘          └──────────┘
        │ 5432              │
   ┌────▼───────────────────▼────┐
   │  DB EC2 (PostgreSQL 컨테이너) │  egress-only(아웃바운드만 NAT 경유)
   └──────────────────────────────┘

  Bastion(public)  : SSH 관문 + Tailscale 서브넷 라우터(VPC 광고)
  NAT instance     : private 서브넷 아웃바운드 중계 (NAT GW 대체, 비용절감)
  온프레 proj-mgmt  : Tailscale 100.x 직결 → DB 복제 / 모니터링 scrape
```
---

## 1.5 배포 순서 (Quick Start)

> State: **개인별 S3 backend + DynamoDB lock** (init/로 부트스트랩)

```bash
# ① (최초 1회) backend 리소스 생성
cd infra/terraform/init && terraform init && terraform apply
terraform output s3_bucket_name                      # 본인 버킷명

# ② backend.hcl (개인 버킷명, gitignore)
cd .. && cp hcl/backend.hcl.example hcl/backend.hcl  # bucket 값 입력

# ③ 인프라 + App
make init        # -backend-config=hcl/backend.hcl 자동
make apply       # 인프라 + App 컨테이너 user_data 기동

# ④ DB 컨테이너 (proj-mgmt 로컬)
make deploy-db   # postgres + S3 백업 cron
```
---

## 2. 사전 준비 (apply 전 필수)

| # | 항목 | 방법 |
|---|------|------|
| 1 | AWS 자격증명 | `aws configure` (개인 계정, region `ap-northeast-2`) |
| 2 | EC2 키페어 `lb-key` | 키페어 자동 생성(tls/local) — 수동 불필요 |
| 3 | `terraform.tfvars` | `terraform.tfvars.example` 복사 후 값 채우기 (아래 4) |
| 4 | Cloudflare 토큰 (cloudflare 사용 시) | `export TF_VAR_cloudflare_api_token="cf_xxx"` (tfvars 금지) |
| 5 | Tailscale provider 키 | `export TF_VAR_tailscale_api_key="tskey-api-xxx"` + tfvars `tailnet_name` |
| 6 | 온프레 Tailscale | proj-mgmt에서 `./bootstrap_tailscale.sh` 실행(서브넷 광고) |

> `admin_ingress_cidr` 은 **default가 없어** 미입력 시 에러납니다(0.0.0.0/0 사고 방지). 본인 공인 IP로 `1.2.3.4/32` 형식 입력.

---

## 3. 파일 구조 & 리소스 인벤토리

```
infra/terraform/
├── provider.tf          # terraform{}·required_providers·3종 provider·(주석)backend
├── variables.tf         # 전 영역 변수 선언 + 검증(validation)
├── terraform.tfvars     # 실제 값 (gitignore — 커밋 금지)
├── terraform.tfvars.example  # 템플릿 (커밋 대상)
├── network.tf           # VPC·IGW·서브넷(멀티AZ)·라우팅 테이블
├── security_groups.tf   # 계층별 SG (alb/bastion/app/db/nat)
├── alb.tf               # ALB·TargetGroup(blue/green)·Listener
├── compute.tf           # NAT·Bastion·App ASG(blue/green)·DB·NAT 라우트
├── iam.tf               # DB→S3 role / Grafana CloudWatch read user
├── storage.tf           # S3 (pg_dump 백업) + 버저닝·차단·수명주기
├── cloudwatch.tf        # SNS·ASG TargetTracking·ALB/TG 알람
├── dns.tf               # ACM + DNS 검증/레코드 (route53 / cloudflare 토글)
├── tailscale.tf         # Tailscale 가입키·기기 대기·서브넷 라우트 승인
└── outputs.tf           # 타 트랙 인터페이스 (IP·ARN·ID·키)
```

### 파일별 핵심 리소스

| 파일 | 핵심 리소스 | 설명 |
|------|------------|------|
| `provider.tf` | `terraform{}`, `provider aws/cloudflare/tailscale` | required_version ≥1.5, aws ~>5.0. S3 backend (backend.hcl 주입). `default_tags`로 전 리소스에 Project/ManagedBy/Track 태깅 |
| `variables.tf` | 변수 30여 개 | 네트워크 CIDR·인스턴스 타입·ASG·DNS 토글·시크릿(sensitive)·exporter 포트. `dns_provider`/`admin_ingress_cidr` 검증 포함 |
| `network.tf` | `aws_vpc`, `aws_internet_gateway`, `aws_subnet`(public/app/db, count), `aws_route_table`(public/private_app/private_db) | VPC 10.0.0.0/16. public=IGW, app=NAT(라우트는 compute.tf), **db=egress-only(NAT 경유)** |
| `security_groups.tf` | `aws_security_group` alb/bastion/app/db/nat + `aws_security_group_rule` app_exporters | ALB→App(80)→DB(5432) 단방향. Bastion=SSH 관문. ⚠️ exporter/pg 룰은 제거됨(Tailscale로 대체) |
| `alb.tf` | `aws_lb`, `aws_lb_target_group` blue/green, `aws_lb_listener` http_redirect/http_forward/https | TG 포트 80, 헬스 `/health` 200. https 모드: 80→443 리다이렉트 + 443 forward. 443 리스너는 `ignore_changes=[default_action]`(배포 전환 보존) |
| `compute.tf` | `data ssm al2023`, `aws_instance` nat/bastion/db, `aws_route` app_nat/**db_nat**, `aws_launch_template` app, `aws_autoscaling_group` blue/green | AMI=AL2023(SSM 최신). NAT=iptables MASQUERADE. Bastion=Tailscale 서브넷라우터. DB=Tailscale 노드+gp3 암호화. **db_nat = DB egress-only 경로** |
| `iam.tf` | `aws_iam_role` db(+S3 정책·instance_profile), `aws_iam_user` grafana_cw(+CloudWatch read·access_key) | DB EC2가 S3에 pg_dump 업로드. Grafana(온프레)용 CloudWatch 읽기 키 발급 |
| `storage.tf` | `aws_s3_bucket` db_backup + versioning·public_access_block·lifecycle | 계정ID 접미사 버킷. 퍼블릭 전면 차단. 7일 후 자동 만료 |
| `cloudwatch.tf` | `aws_sns_topic` alerts, `aws_autoscaling_policy` app_cpu(+green), `aws_cloudwatch_metric_alarm` alb_5xx/tg_unhealthy | CPU 60% TargetTracking 스케일아웃. ALB 5xx·UnHealthyHost 알람→SNS |
| `dns.tf` | `aws_acm_certificate`, route53/cloudflare 레코드, `aws_acm_certificate_validation` | `dns_provider`로 한쪽만 생성. **검증 순서는 depends_on으로 보장**(cloudflare race 차단) |
| `tailscale.tf` | `tailscale_tailnet_key` ec2_join, `data tailscale_device` bastion/db, `tailscale_device_subnet_routes` bastion | 가입키 생성(preauthorized). Bastion 기기 대기→VPC 라우트 자동승인. DB 기기 대기(복제 IP 확보) |
| `outputs.tf` | 14개 output | 타 트랙 인터페이스(아래 5) |

---

## 4. 실행 순서 & 의존 그래프

Terraform이 의존성으로 순서를 자동 결정하지만, 이해를 위한 논리 계층은 다음과 같습니다:

```
network (VPC·서브넷·라우팅)
   ├─▶ security_groups
   ├─▶ storage (S3) ── iam (role/user) ──┐
   └─▶ alb (TG·Listener)                 │
            │                            │
   compute ─┤  NAT → app_nat/db_nat 라우트 → Bastion → LaunchTemplate → ASG(blue/green) → DB
            │
   tailscale ──▶ (Bastion/DB 기기 대기 wait_for 180s) ──▶ 서브넷 라우트 승인
   dns ──▶ ACM 발급 → 검증레코드(route53/cloudflare) → 검증완료 대기
   cloudwatch ──▶ ASG/ALB 대상 스케일·알람
```

**apply 중 멈추는(블로킹) 두 구간 — 정상입니다:**
1. `tailscale_device` `wait_for=180s` — EC2가 tailnet에 가입할 때까지 대기. 부팅이 느리면 실패할 수 있음(재apply로 해결).
2. `aws_acm_certificate_validation` — ACM이 DNS 검증 레코드를 확인할 때까지 대기(수 분).

---

## 5. 다른 트랙과의 인터페이스 (필수)

### 내가 내보내는 것 (outputs.tf → 소비처)

| output | 소비 트랙 | 용도 |
|--------|----------|------|
| `alb_dns_name` / `service_domain` | B·C·E | 서비스 접근·배포 검증 |
| `tg_blue_arn` / `tg_green_arn` | C·E | 배포 전환·Rollback (TG 스위치) |
| `asg_names` (map) | C | 배포 대상 ASG |
| `bastion_public_ip` / `bastion_private_ip` | 전체 | SSH 관문 |
| `db_private_ip` | B·D | 앱 DB 연결·모니터링 |
| `db_tailscale_ip` | 온프레 | proj-mgmt replica → DB `100.x:5432` 복제 |
| `nat_public_ip` | 운영 | 아웃바운드 IP 확인 |
| `sg_ids` (map) | 전체 | SG 참조 |
| `db_backup_bucket` | A·B | pg_dump 백업 대상 |
| `alerts_sns_arn` | D | CloudWatch 알람 연동(백업 경로) |
| `grafana_cw_access_key_id` / `grafana_cw_secret_access_key` | **D** | **Grafana CloudWatch datasource (핵심 핸드오프)** |

> 시크릿 출력은 `terraform output -raw grafana_cw_secret_access_key` 로 확인.

### 내가 받아야 하는 것 (입력 — 미결 포함)

| 어디서 | 무엇을 | 상태 |
|--------|--------|------|
| 강사 가이드 | AMI(AL2023/SSM)·인스턴스 타입 정책 | 반영됨 |
| B 트랙 | `/health → 200` 컨테이너(:80) + Docker Hub 이미지 | **ASG 0대 해제 조건** (≈6/8) |
| B 트랙 | DB read/write 엔드포인트 env화 | 요청 |
| D 트랙 | App 메트릭 scrape 경로(#3 — App을 Tailscale 노드로) | 결정: (a), 구현 예정 |
| E 트랙 | fail2ban 차단지점(NACL/nginx) | 정정 필요 |

---

## 6. 주요 설계 결정 (왜 이렇게 했나)

- **local state**: 개인 AWS 계정 독립 실행 → S3 backend 불필요. `terraform.tfstate`는 로컬 보관·**커밋 금지**(`.gitignore *.tfstate`).
- **App ASG 초기 0대(staging)**: `asg_min/desired=0`. 앱(`/health 200`) 배포 전 ELB 헬스체크가 인스턴스를 무한 교체(thrash)·비용 누수하는 것을 방지. **해제 조건**: B 이미지가 Docker Hub에 올라오면 `asg_min/desired=1` + launch template에 `docker pull/run` 추가.
- **DB egress-only**: 인바운드 0, 아웃바운드만 NAT 경유(`aws_route.db_nat`). 패키지·pg_dump 업로드용. 인터넷에서 DB로 들어오는 경로는 없음.
- **NAT instance(≠NAT GW)**: 비용 절감. `source_dest_check=false` + iptables MASQUERADE.
- **Tailscale 노드-투-노드(L3)** — VXLAN 폐기: DB 복제·모니터링은 TCP라 L2 불필요. `accept-routes=false` 유지(VPC 라우트 주입 시 VSCode Remote-SSH 끊김 — project1 이슈). 노드 간 `100.x` 메시는 accept-routes와 무관하게 동작.
- ⚠️ **exporter/pg SG 룰은 Tailscale 트래픽에 적용되지 않음**: AWS SG는 ENI(eth0)만 필터링하는데 Tailscale 트래픽은 암호화 터널(tailscale0)로 들어와 SG를 우회함. 실제 접근통제는 **Tailscale ACL + pg_hba.conf**로 한다. (SG 룰은 비통제 — 정리 예정)
- **DNS 토글**: `dns_provider=route53`(팀원) / `cloudflare`(신준한) / `none`. cloudflare는 ACM 검증 레코드를 실제 DNS에 넣어야 검증됨(수업 때 Route53에 넣어 실패했던 부분 해결).
- **CloudWatch=AWS 인프라 계층, Prometheus=앱/컨테이너/pg**: 알림 발송은 D의 Grafana/Alertmanager→Telegram으로 통일(별도 Lambda 미사용). SNS 토픽/알람은 AWS 콘솔 가시성·백업 경로로만 유지.

---

## 6.5 Tailscale 연결 구조 (node-to-node) — 팀원 안내

### 한 줄 요약
Tailscale은 **회원 전용 무전기 네트워크**입니다. 가입한 기기마다 고유 번호(`100.x`)를 받고, **회원끼리는 번호만 알면 양방향 직통**입니다(`accept-routes` 설정과 무관). 우리는 서버를 "라우터 뒤에 숨기는" 대신 **각자 회원으로 가입(node-to-node)** 시켜서 온프레(proj-mgmt) ↔ AWS를 연결합니다.

### 두 가지 모델 (우리가 고른 것 = 노드)
| | 노드 (우리 선택) | 서브넷 라우터 |
|---|---|---|
| 동작 | 기기가 직접 가입 → `100.x` 직통 | 한 기기가 "내 뒤 대역 다 받아"라고 광고 |
| `accept-routes` | **false 유지 가능** (VS Code 보호) | 소비자가 **true 필요** → 대역 충돌 위험 |
| 우리 적용 | App·DB·proj-mgmt | Bastion(휴면 break-glass) |

> **왜 accept-routes=false?** proj-mgmt가 AWS 대역(또는 겹치는 172.16.x)을 라우팅 테이블에 받으면 VS Code SSH가 끊기는 충돌이 납니다. 노드 직통은 이 설정과 무관하게 동작하므로 false로 둡니다.

### 기기별 역할 / 플래그 / 코드 위치
| 기기 | 역할 | Tailscale 플래그 | 코드 위치 |
|---|---|---|---|
| **Bastion** | SSH 관문 + (휴면)서브넷 라우터 | `--advertise-routes=VPC --accept-routes` | `compute.tf` (bastion user_data), `tailscale.tf` `approve_vpc_routes` |
| **DB** | 노드 (복제·Ansible 직결) | `--accept-routes=false` (광고 없음) | `compute.tf` (db user_data), `tailscale.tf` `db_device` |
| **App (ASG)** | ephemeral 노드 (메트릭 scrape) | `--accept-routes=false`, tag:app | `compute.tf` (App LT), `tailscale.tf` `app_join` |
| **proj-mgmt** | 노드 (모니터링·IaC 실행) | `--advertise-routes=172.16.x --accept-routes=false` | `bootstrap_tailscale.sh` |

### 코드 위치별 설명
- **`tailscale.tf`**
  - `tailscale_tailnet_key.ec2_join` — Bastion·DB 공통 가입키(영구).
  - `tailscale_tailnet_key.app_join` — App ASG 전용 **ephemeral + tag:app** 키(스케일인 시 노드 자동 삭제).
  - `data.tailscale_device.bastion_device` + `tailscale_device_subnet_routes.approve_vpc_routes` — Bastion이 광고한 VPC 경로를 자동 승인(휴면 break-glass).
  - `data.tailscale_device.db_device` — DB의 `100.x`를 조회해 outputs/inventory로 전달.
- **`compute.tf`** — 각 인스턴스 user_data의 `tailscale up`. Bastion만 `--advertise-routes`(라우터), DB·App은 광고 없이 `--accept-routes=false`(노드).
- **`outputs.tf`** — `db_tailscale_ip` = DB의 `100.x` (proj-mgmt replica가 이 주소:5432로 복제).
- **`ansible.tf`** — `db_ts_ip`를 inventory의 `ansible_host`로 사용 → proj-mgmt가 DB의 `100.x`로 직접 SSH(Bastion 안 거침).
- **`bootstrap_tailscale.sh`** (온프레) — proj-mgmt를 노드로 가입. `--accept-routes=false`(VS Code 보호).

### 가상 연결도 (tailnet 100.x 메시)
```
        온프레                         AWS (VPC 10.0.0.0/16)
  ┌──────────────┐                ┌───────────────────────────┐
  │ proj-mgmt    │  100.x 직통    │  Bastion(노드+휴면라우터)   │  ← break-glass: SSH 점프
  │ (모니터링·IaC)│◄──────────────►│                           │
  │ accept=false │       │        │  DB(노드) 100.x:5432       │  ← 복제·Ansible
  └──────────────┘       ├───────►│  App(ephemeral 노드)       │  ← 메트릭 scrape
                         │        │   tag:app 100.x:9100/...   │
                  (모두 node-to-node, 서브넷 광고 미사용)
```

### 데이터 흐름 (누가 누구에게, 100.x로)
| 흐름 | 방향 | 비고 |
|---|---|---|
| 메트릭 scrape | proj-mgmt → App/DB `100.x:포트` | pull (Prometheus). SG 우회(tailscale0), 통제=ACL |
| DB 복제 | proj-mgmt → DB `100.x:5432` | `accept-routes`와 무관 |
| Ansible 배포 | proj-mgmt → DB `100.x:22` | inventory `ansible_host` |
| break-glass | proj-mgmt → Bastion `100.x` → 사설 SSH | Tailscale 장애 대비 비상 경로 |

> **중요:** Tailscale 트래픽은 `tailscale0`로 들어와 **AWS Security Group(ENI)을 우회**합니다. 그래서 SG 인바운드 규칙이 아니라 **Tailscale ACL + `pg_hba`**가 실제 통제점입니다.

### App 동적 디스커버리 (왜 App만 추가 장치가 필요한가)
DB는 1대 고정이라 `data.tailscale_device`로 IP를 한 번 잡으면 끝입니다. 하지만 **App은 ASG라 공격 시 인스턴스가 늘고 IP(`100.x`)가 계속 바뀝니다.** 그래서 정적 타깃 대신, `tag:app` 기기 목록을 Tailscale API로 물어 Prometheus 타깃을 갱신하는 **http_sd 헬퍼**(`monitoring/tailscale-sd/`)를 둡니다.

### 검증 명령
```bash
tailscale status                      # 각 노드 100.x 확인 (app-*, lb-db 등)
curl -s http://localhost:9999/app-targets | jq    # 헬퍼가 현재 App 타깃을 뱉는지
# Prometheus UI → Status → Targets 에서 app-nodes up=1 확인
```

---

## 7. 실행·테스트 방법

```bash
# 레포 루트(~/project2-security)에서 make 사용
make init        # terraform init
make fmt         # terraform fmt -recursive
make validate    # terraform validate
make plan        # 변경 미리보기
make apply       # 인프라 생성 (확인 프롬프트, -parallelism=3)
make output      # 타 트랙이 가져갈 IP·ID·ARN 확인
make destroy     # 전체 삭제 (실습 후 비용 절감)
```

> `make apply`는 `-parallelism=3`으로 동작(개인 계정 rate limit 완화). 직접 쓰려면 `cd infra/terraform && terraform <cmd>`.

---

## 8. 알려진 이슈 / 주의

- **App이 아직 Tailscale 노드가 아님** → 현재 App 메트릭 scrape 불가. #3 결정(a)에 따라 launch template user_data에 `tailscale up`(ephemeral·tag) 추가 예정.
- **tailscale_device wait_for(180s)**: 부팅 지연 시 apply 실패 가능 → 재apply 또는 wait 상향.
- **tailscale_tailnet_key ephemeral=false**: destroy 후 재apply 시 동일 hostname의 stale device가 남아 `data.tailscale_device`가 오매칭될 수 있음 → 데모 reset 시 Admin 콘솔에서 수동 정리.
- **lb-key 사전 생성 필수**: 없으면 EC2 생성 실패.
- **`make backup` 타깃 부재**: check.sh가 안내하나 Makefile에 미구현 → 추가 또는 안내 정정 필요(비차단).
- **tg_unhealthy 알람이 blue TG만 감시**: Green 전환 후 사각지대 — green 알람 추가 검토.

---

## 9. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-05-30 | 초안 작성, 디렉토리 구조 확정 | 신준한 |
| 2026-06-04 | 현재 13개 .tf 기준 전면 갱신: local state·ALB·ASG(blue/green)·CloudWatch·IAM·S3·DNS 토글·Tailscale 노드-투-노드(VXLAN 폐기) 반영. DB egress-only·ASG 0대 staging·SG/Tailscale 통제 주의 추가 | 신준한 |