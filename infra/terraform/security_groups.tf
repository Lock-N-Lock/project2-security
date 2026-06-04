# ================================================================
# security_groups.tf — 계층별 SG (최소 권한 원칙)
# ALB → App → DB 단방향, Bastion=SSH 관문, NAT=App 아웃바운드
# exporter(D 트랙 scrape) — 앱은 compose(단일 호스트), Swarm 미사용
# 파일위치 : ~/project2-security/infra/terraform/security_groups.tf
# ================================================================

# ── ALB SG : 인터넷 → 80/443 ──────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "ALB ingress 80/443 from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

# ── Bastion SG : 관리자 IP → SSH ──────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${var.project}-bastion-sg"
  description = "Bastion SSH from admin, Tailscale subnet router"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ingress_cidr]
  }

  # Tailscale: 인바운드 포트 개방 불필요 (아웃바운드 UDP/443 으로 NAT 통과)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-bastion-sg" }
}

# ── App SG : ALB → 80/8000, Bastion → SSH, Swarm/exporter ──
resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "App tier: from ALB, Bastion, Swarm overlay, exporters"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}

# exporter scrape : 온프레 Prometheus 가 VXLAN overlay(10.10.10.0/24) 로 접근
resource "aws_security_group_rule" "app_exporters" {
  for_each = toset([for p in var.exporter_ports : tostring(p)])

  type              = "ingress"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  security_group_id = aws_security_group.app.id
  cidr_blocks       = [var.onprem_overlay_cidr]
  description       = "Prometheus scrape ${each.value} from overlay"
}

# ── DB SG : App → 5432, Bastion → SSH, pg_exporter ─────────
resource "aws_security_group" "db" {
  name        = "${var.project}-db-sg"
  description = "DB tier: PostgreSQL from App only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from App"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "postgres_exporter from overlay"
    from_port   = 9187
    to_port     = 9187
    protocol    = "tcp"
    cidr_blocks = [var.onprem_overlay_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-db-sg" }
}

# ── NAT instance SG : App 서브넷 → 인터넷 중계 ─────────────
resource "aws_security_group" "nat" {
  name        = "${var.project}-nat-sg"
  description = "NAT instance: forward private subnet egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "from app subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    # DB의 S3 백업 및 온프레미스 Replication 통로 개방
    cidr_blocks = concat(var.app_subnet_cidrs, var.db_subnet_cidrs)
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-nat-sg" }
}