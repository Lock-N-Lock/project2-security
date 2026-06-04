# =============================================================
# alb.tf — ALB + Target Group(Blue/Green) + Listener
# Rollback = Target Group 전환 (배포성공=Green, 실패=Blue)
# C/E 트랙이 이 TG ARN 으로 전환 스크립트 작성
# 파일위치 : ~/project2-security/infra/terraform/alb.tf
# =============================================================

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.project}-alb" }
}

# ── Target Group : Blue / Green ───────────────────────────
resource "aws_lb_target_group" "blue" {
  name     = "${var.project}-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name  = "${var.project}-tg-blue"
    Color = "blue"
  }
}

resource "aws_lb_target_group" "green" {
  name     = "${var.project}-tg-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name  = "${var.project}-tg-green"
    Color = "green"
  }
}

# ── Listener ──────────────────────────────────────────────
# HTTPS 사용 시: HTTP(80)→443 리다이렉트 + HTTPS(443) forward
# HTTP 전용 시:  HTTP(80) forward (count 로 listener 자체를 분기 → 견고)

# [HTTPS 모드] 80 → 443 redirect
resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# [HTTP 전용 모드] 80 → forward blue
resource "aws_lb_listener" "http_forward" {
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# [HTTPS 모드] 443 forward blue (Rollback 시 TG 전환)
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.dns_provider == "none" ? aws_acm_certificate.main[0].arn : aws_acm_certificate_validation.main[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # Rollback 전환은 운영 중 TG 변경 → default_action 변경 무시
  lifecycle {
    ignore_changes = [default_action]
  }
}