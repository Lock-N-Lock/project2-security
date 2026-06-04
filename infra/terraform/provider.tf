# =============================================================
# provider.tf — Terraform Provider 설정
# 개인 AWS 계정 독립 실행 → local state (S3 backend 미사용)
# DNS provider 토글: route53(팀원) / cloudflare(신준한)
# 파일위치 : ~/project2-security/infra/terraform/provider.tf
# =============================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    tailscale = { # ← 추가
      source  = "tailscale/tailscale"
      version = "~> 0.16" # 수업에서 쓰던 버전으로 맞추세요
    }
  }
  # terraform 상태 관리를 위한 remote 백엔드 설정
  backend "s3" {
    # 비워둔 값은 외부 파일(backend.hcl)에서 채우기
    bucket         = ""                         # 미리 생성한 s3 버킷의 이름
    key            = "infra/terraform.tfstate"  # /infra/하위에 만들어 지도록
    region         = "ap-northeast-2"           
    dynamodb_table = ""                         # 미리 준비된 dynamodb 테이블의 이름을 명시하면 lock 상태가 자동으로 관리된다.
    encrypt        = true                       # tfstate에는 민감한 정보가 있을 수 있기 때문에 암호화
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "Terraform"
      Track     = "A-Infra"
    }
  }
}

# Cloudflare provider — dns_provider = "cloudflare" 일 때만 사용
# 토큰은 코드에 두지 말고 환경변수 TF_VAR_cloudflare_api_token 로 주입
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Tailscale provider — 키 생성·기기 승인용 (api_key 는 환경변수 권장)
provider "tailscale" {
  tailnet = var.tailnet_name
  api_key = var.tailscale_api_key
}