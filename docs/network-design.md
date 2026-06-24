# 네트워크 설계서 (A 트랙 산출물)

> 이 문서는 `infra/terraform/`의 .tf 코드와 1:1로 대응하는 기술 원본(source of truth)입니다.
> 발표용 정리본·다이어그램은 Notion에 별도로 두고 이 문서를 참조합니다.

>파일 위치 : ~/project2-security/docs/network-design.md

| 항목 | 내용 |
|------|------|
| 최종 수정 | 2026-06-22 |
| 담당 | 신준한 |
| 상태 | 코드 반영 완료 (.tf 기준 동기화) |

## 0. SG 명칭 (실제 리소스)

역할 기반 SG. `${var.project}` prefix는 `lb`.

| SG 이름 | 보호 대상 | 서브넷 | 한 줄 설명 |
|---------|-----------|--------|-----------|
| `lb-alb-sg` | ALB | 퍼블릭 | 인터넷 → 80/443 진입점 |
| `lb-bastion-sg` | Bastion 호스트 | 퍼블릭 | 관리자 SSH 점프 서버 |
| `lb-nat-sg` | NAT instance | 퍼블릭 | 사설 서브넷 아웃바운드 경유지 |
| `lb-app-sg` | App ASG (Blue/Green) | 프라이빗(App) | Nginx + FastAPI (Blue-Green 공용) |
| `lb-db-sg` | DB | 프라이빗(DB) | PostgreSQL |

## 1. CIDR 설계 (다중 AZ)

| 구분 | CIDR | AZ | 비고 |
|------|------|----|----|
| VPC | 10.0.0.0/16 | — | |
| 퍼블릭 | 10.0.1.0/24 | ap-northeast-2a | Bastion·NAT·ALB |
| 퍼블릭 | 10.0.2.0/24 | ap-northeast-2c | ALB (다중 AZ) |
| 프라이빗(App) | 10.0.11.0/24 | ap-northeast-2a | App ASG |
| 프라이빗(App) | 10.0.12.0/24 | ap-northeast-2c | App ASG |
| 프라이빗(DB) | 10.0.21.0/24 | ap-northeast-2a | PostgreSQL |

> ALB·App ASG는 2개 AZ(2a/2c)에 걸쳐 배치(고가용성). DB는 단일 AZ(2a).

## 2. 라우팅

| 라우팅 테이블 | 연결 서브넷 | 경로 |
|---------------|-------------|------|
| lb-public-rt | 퍼블릭(2a/2c) | 0.0.0.0/0 → IGW |
| lb-app-rt | 프라이빗(App) | 0.0.0.0/0 → NAT instance |
| lb-db-rt | 프라이빗(DB) | **egress-only** (NAT 경유 아웃바운드만, 인바운드 인터넷 차단) |

> DB 서브넷은 보안 격리: 인바운드 인터넷 없음. S3 백업·패키지 업데이트용 아웃바운드만 NAT 경유.
> `0.0.0.0/0 → NAT` 경로는 NAT instance 생성 후 `compute.tf`의 `aws_route`로 추가됩니다.

## 3. EC2 / ASG 배치

| 이름 | SG | 서브넷 | 사설 IP | 역할 |
|------|----|--------|---------|------|
| lb-bastion | lb-bastion-sg | 퍼블릭(2a) | 10.0.1.x | SSH 진입점 |
| lb-nat | lb-nat-sg | 퍼블릭(2a) | 10.0.1.x | NAT (게이트웨이 대체) |
| lb-asg-blue | lb-app-sg | 프라이빗(App, 2a/2c) | 동적(ASG) | 운영 앱 (desired=`var.asg_desired`) |
| lb-asg-green | lb-app-sg | 프라이빗(App, 2a/2c) | 동적(ASG) | 예비 (desired=0, 전환 시 확장) |
| lb-db | lb-db-sg | 프라이빗(DB, 2a) | 10.0.21.x | PostgreSQL |

> App은 Launch Template + ASG(Blue/Green)라 IP 고정이 아닌 **동적 할당**. ALB Target Group(blue/green)으로 라우팅.

## 4. Security Group 매트릭스 (.tf 반영)

> 진입 흐름: 인터넷 → ALB(80/443) → App(80) → DB(5432). Bastion=SSH 관문.
> 모니터링·DB복제는 SG가 아닌 Tailscale 노드망 경유(5번 참조).

### lb-alb-sg (ALB)
| 방향 | 포트 | 소스/대상 | 용도 |
|------|------|-----------|------|
| ingress | TCP 80 | 0.0.0.0/0 | HTTP |
| ingress | TCP 443 | 0.0.0.0/0 | HTTPS (`enable_https=true` 시) |
| egress | ALL | 0.0.0.0/0 | App 전달 |

### lb-bastion-sg (Bastion)
| 방향 | 포트 | 소스/대상 | 용도 |
|------|------|-----------|------|
| ingress | TCP 22 | `var.admin_ingress_cidr` | 관리자 SSH |
| egress | ALL | 0.0.0.0/0 | 사설망·인터넷 |

> Tailscale은 아웃바운드 UDP/443으로 NAT 통과 → 인바운드 개방 불필요.

### lb-app-sg (App ASG)
| 방향 | 포트 | 소스/대상 | 용도 |
|------|------|-----------|------|
| ingress | TCP 80 | lb-alb-sg | ALB → Nginx |
| ingress | TCP 22 | lb-bastion-sg | Bastion 경유 SSH |
| egress | ALL | 0.0.0.0/0 | DB·이미지 pull·Tailscale |

### lb-db-sg (DB)
| 방향 | 포트 | 소스/대상 | 용도 |
|------|------|-----------|------|
| ingress | TCP 5432 | lb-app-sg | 앱 → DB |
| ingress | TCP 22 | lb-bastion-sg | Bastion 경유 SSH |
| egress | ALL | 0.0.0.0/0 | NAT 경유 (S3 백업·업데이트) |

### lb-nat-sg (NAT instance)
| 방향 | 포트 | 소스/대상 | 용도 |
|------|------|-----------|------|
| ingress | ALL | app·db 서브넷 CIDR | 사설 서브넷 아웃바운드 중계 |
| ingress | TCP 22 | lb-bastion-sg | Bastion 경유 SSH |
| egress | ALL | 0.0.0.0/0 | 인터넷 |

> **모니터링 포트(9100/9113/9105/9187)는 SG에 없습니다** — VPC가 아닌 Tailscale 노드망(100.x)으로 scrape하기 때문(5번).

## 5. 모니터링·DB복제 경로 (Tailscale 노드망)

App·DB의 exporter는 VPC 사설망이 아니라 **Tailscale L3 노드망(100.x)**으로 수집합니다. proj-mgmt(on-prem)의 Prometheus가 Tailscale SD(`tailscale-sd`)로 노드를 자동 발견해 scrape합니다.

- **메트릭 수집**: proj-mgmt Prometheus → (Tailscale 100.x) → App/DB exporter
- **DB 복제**: proj-mgmt replica → (Tailscale 100.x:5432) → AWS DB
- 퍼블릭 포트·SG 개방 불필요 (노드-투-노드 L3)

## 6. exporter / 포트 목록 (D 트랙 인터페이스)

| 대상 | exporter | 포트 | 수집 경로 |
|------|----------|------|-----------|
| App (OS) | node_exporter | 9100 | Tailscale SD |
| App (Nginx) | nginx_exporter | 9113 | Tailscale SD |
| App (Nginx 로그) | nginx_log_metrics | 9105 | Tailscale SD |
| DB (OS) | node_exporter | 9100 | Tailscale SD |
| DB (PostgreSQL) | postgres_exporter | 9187 | Tailscale SD |
| 모니터링 호스트(on-prem) | Prometheus 9090 / Grafana 3000 / Alertmanager 9093 / Loki 3100 | — | 로컬 |