# =============================================================
# network.tf — VPC / 서브넷(멀티-AZ) / IGW / 라우팅
# 프라이빗 0.0.0.0/0 → NAT instance 경로는 compute.tf 에서 추가
# 파일위치 : ~/project2-security/infra/terraform/network.tf
# =============================================================

locals {
  # az 끝 글자 추출: "ap-northeast-2a" → "a"
  az_suffix = [for az in var.azs : replace(az, var.aws_region, "")]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# --- 서브넷 ---
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${local.az_suffix[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  count             = length(var.app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-app-${local.az_suffix[count.index]}"
    Tier = "app"
  }
}

resource "aws_subnet" "db" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-db-${local.az_suffix[count.index]}"
    Tier = "db"
  }
}

# --- 퍼블릭 라우팅 (IGW) ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project}-public-igw" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- 프라이빗(App) 라우팅: NAT instance 경유 ---
# 0.0.0.0/0 → NAT 경로는 compute.tf 에서 aws_route 로 추가 (NAT instance 생성 후)
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-nat-app" }
}

resource "aws_route_table_association" "app" {
  count          = length(aws_subnet.app)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# --- 프라이빗(DB) 라우팅: 인터넷 경로 없음(격리) ---
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-db" }
}

resource "aws_route_table_association" "db" {
  count          = length(aws_subnet.db)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.private_db.id
}