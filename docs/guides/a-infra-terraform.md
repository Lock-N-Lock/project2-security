# [A] 인프라·Terraform 가이드

| 항목 | 내용 |
|------|------|
| 트랙 | A — 인프라·IaC |
| 담당 | 신준한 (main) / 박정은 (sub) |
| 디렉토리 | `infra/terraform/`, `infra/ansible/` |
| 최종 수정 | 2026-05-30 |

## 1. 개요

AWS 위에 프로젝트의 모든 네트워크·컴퓨트 토대를 Terraform으로 프로비저닝합니다. VPC·서브넷·라우팅·Security Group·EC2(Bastion, App Blue, Green, DB)를 코드로 정의하며, 다른 모든 트랙이 이 인프라 위에서 동작합니다.

## 2. 디렉토리·파일 구조

```
infra/terraform/
├── backend.tf          # S3 원격 state + DynamoDB 잠금 (팀 공유)
├── provider.tf         # AWS provider·region·버전 제약
├── variables.tf        # 변수 선언
├── terraform.tfvars    # 실제 값 (CIDR·인스턴스 타입·키명)
├── network.tf          # VPC, IGW, NAT, subnet x3, route table
├── security_groups.tf  # lb-sg-web / lb-sg-con / lb-sg-rec
├── compute.tf          # bastion, app(Blue), green, db EC2
└── outputs.tf          # IP·ID 출력 (C·D 트랙 소비)
```

## 3. 핵심 동작 흐름

1. `backend.tf`가 S3에 state를 저장하고 DynamoDB로 동시 apply를 잠가 팀 충돌을 방지합니다.
2. `network.tf`가 VPC(10.0.0.0/16)와 퍼블릭·프라이빗(App/DB) 서브넷, IGW·NAT 라우팅을 만듭니다.
3. `security_groups.tf`가 계층별 SG를 정의합니다(설계서 SG 매트릭스 기준).
4. `compute.tf`가 Bastion·App(Blue)·예비(Green)·DB EC2를 띄웁니다.
5. `outputs.tf`가 다른 트랙이 쓸 IP·ID를 내보냅니다.

## 4. 다른 트랙과의 인터페이스 (필수)

**내가 받는 것 (입력)**

| 어디서 | 무엇을 | 형식·경로 |
|--------|--------|-----------|
| 강사 가이드 | 인스턴스 타입·AMI 정책 | 수업 기준 |
| B 트랙 | 앱이 필요로 하는 포트 | 협의 |

**내가 내보내는 것 (출력)**

| 어디로 | 무엇을 | 형식·경로 |
|--------|--------|-----------|
| C 트랙 | Bastion public IP, App/Green private IP | `terraform output` / `outputs.tf` |
| C 트랙 | 배포 대상 SSH 접근 정보 | `outputs.tf` |
| D 트랙 | 모니터링 대상 instance IP, exporter 포트 | `outputs.tf` |
| 전 트랙 | VPC ID, Subnet ID, SG ID | `outputs.tf` |

## 5. 실행·테스트 방법

```bash
cd infra/terraform
terraform init      # backend·provider 초기화
terraform plan      # 변경 미리보기
terraform apply     # 실제 생성
terraform output    # 다른 트랙이 가져갈 값 확인
```

## 6. 트러블슈팅 / 알려진 이슈

- backend용 S3 버킷·DynamoDB 테이블은 `terraform init` 전에 먼저 존재해야 함(닭-달걀). CLI로 1회 수동 생성 후 backend 연결.

## 7. 변경 이력

| 날짜 | 변경 내용 | 작성자 |
|------|-----------|--------|
| 2026-05-30 | 초안 작성, 디렉토리 구조 확정 | 신준한 |