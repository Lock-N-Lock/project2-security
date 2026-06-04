# 네트워크 설계서 (A 트랙 산출물)

> 이 문서는 `infra/terraform/`의 .tf 코드와 1:1로 대응하는 기술 원본(source of truth)입니다.
> 발표용 정리본·다이어그램은 Notion에 별도로 두고 이 문서를 참조합니다.

>파일 위치 : ~/project2-security/docs/network-design.md

| 항목 | 내용 |
|------|------|
| 최종 수정 | 2026-05-30 |
| 담당 | 신준한 |
| 상태 | 작성 중 (SG 룰 초안 검토 필요) |

## 0. SG 명칭 정리 (중요)

기존 컨텍스트의 `lb-sg-web / con / rec`는 수업 참고 아키텍처(ccmall, "이미지 3")에서 가져온 약어로, project2의 실제 구성요소(Bastion·NAT·App·DB)와 맞지 않습니다.
따라서 **역할 기반 SG 이름**으로 재정리합니다.

| SG 이름 | 보호 대상 | 서브넷 | 한 줄 설명 |
|---------|-----------|--------|-----------|
| `lb-sg-bastion` | Bastion 호스트 | 퍼블릭 | 관리자가 사설망에 진입하는 SSH 점프 서버 |
| `lb-sg-nat` | NAT instance | 퍼블릭 | 사설 서브넷의 아웃바운드 인터넷 경유지 |
| `lb-sg-app` | App Blue / Green | 프라이빗(App) | Nginx + FastAPI 앱 서버 (Blue-Green 공용) |
| `lb-sg-db` | DB | 프라이빗(DB) | PostgreSQL |

## 1. CIDR 설계

| 구분 | 이름 | CIDR | 비고 |
|------|------|------|------|
| VPC | lb-vpc | 10.0.0.0/16 | |
| 퍼블릭 서브넷 | lb-public-subnet | 10.0.1.0/24 | Bastion·NAT |
| 프라이빗(App) | lb-private-app-subnet | 10.0.2.0/24 | App Blue/Green |
| 프라이빗(DB) | lb-private-db-subnet | 10.0.3.0/24 | PostgreSQL |

## 2. 라우팅

| 라우팅 테이블 | 연결 서브넷 | 기본 경로 |
|---------------|-------------|-----------|
| lb-public-igw | 퍼블릭 | 0.0.0.0/0 → IGW |
| lb-private-nat | 프라이빗(App/DB) | 0.0.0.0/0 → NAT instance |

## 3. EC2 배치

| 이름 | SG | 서브넷 | 사설 IP | 역할 |
|------|----|--------|---------|------|
| lb-bastion | lb-sg-bastion | 퍼블릭 | 10.0.1.x | SSH 진입점 |
| lb-nat | lb-sg-nat | 퍼블릭 | 10.0.1.x | NAT (게이트웨이 대체) |
| lb-app-blue | lb-sg-app | 프라이빗(App) | 10.0.2.20 | 운영 앱 |
| lb-app-green | lb-sg-app | 프라이빗(App) | 10.0.2.30 | 예비(Green) |
| lb-db | lb-sg-db | 프라이빗(DB) | 10.0.3.x | PostgreSQL |

## 4. Security Group 매트릭스 (초안 — 검토·확정 필요)

> 포트 출처: 앱(FastAPI 8000), Nginx(80), PostgreSQL(5432), node_exporter(9100), nginx_exporter(9113).
> `<관리자IP>`, `<모니터링소스>`는 확정 후 치환합니다(아래 5·6번 결정사항 참조).

### lb-sg-bastion (Bastion)
| 방향 | 프로토콜/포트 | 소스/대상 | 용도 |
|------|---------------|-----------|------|
| ingress | TCP 22 | `<관리자 공인 IP>/32` | 관리자 SSH 접속 |
| egress | ALL | 0.0.0.0/0 | 사설망·인터넷 |

### lb-sg-nat (NAT instance)
| 방향 | 프로토콜/포트 | 소스/대상 | 용도 |
|------|---------------|-----------|------|
| ingress | ALL | 10.0.2.0/24, 10.0.3.0/24 | 사설 서브넷 아웃바운드 |
| egress | ALL | 0.0.0.0/0 | 인터넷 |

### lb-sg-app (App Blue/Green)
| 방향 | 프로토콜/포트 | 소스/대상 | 용도 |
|------|---------------|-----------|------|
| ingress | TCP 22 | lb-sg-bastion | Bastion 경유 SSH 관리 |
| ingress | TCP 80 | `<진입점: ALB SG 또는 Bastion>` | HTTP(Nginx) |
| ingress | TCP 9100 | `<모니터링소스>` | node_exporter |
| ingress | TCP 9113 | `<모니터링소스>` | nginx_exporter |
| egress | ALL | 0.0.0.0/0 | DB·외부(이미지 pull 등) |

### lb-sg-db (DB)
| 방향 | 프로토콜/포트 | 소스/대상 | 용도 |
|------|---------------|-----------|------|
| ingress | TCP 5432 | lb-sg-app | 앱 → DB 접속만 허용 |
| ingress | TCP 9100 | `<모니터링소스>` | node_exporter (선택) |
| egress | ALL | 0.0.0.0/0 | NAT 경유 업데이트 |

## 5. 결정사항 (확정 후 위 표 치환)

- `<관리자 공인 IP>`: Bastion SSH를 허용할 관리자 IP. (집·학원 공인 IP 등)
- 앱 HTTP(80) 진입점: ALB를 둘지 / Bastion 경유로만 접근할지 결정.
- on-prem(proj-mgmt VMware) -> AWS 사설 서브넷 **모니터링·Ansible 경로**:
  Bastion ProxyCommand 경유 / VPN 중 무엇으로 할지. 이게 `<모니터링소스>`를 결정함.

## 6. exporter / 포트 목록 (D 트랙 인터페이스)

| 대상 | exporter | 포트 |
|------|----------|------|
| App Blue/Green (OS) | node_exporter | 9100 |
| App Blue/Green (Nginx) | nginx_exporter | 9113 |
| DB (OS, 선택) | node_exporter | 9100 |
| 모니터링 호스트(on-prem) | Prometheus 9090 / Grafana 3000 / Alertmanager 9093 | |