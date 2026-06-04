# =============================================================
# tailscale.tf — Tailscale 가입키 + 기기/라우트 자동 승인 (수업 test05_tailscale3 패턴)
#  Bastion=서브넷 라우터(VPC 광고) / DB=노드(복제 직결용)
#  파일위치 : ~/project2-security/infra/terraform/tailscale.tf
# =============================================================

# EC2 공통 가입키 (preauthorized=자동승인, reusable=재생성 대비)
resource "tailscale_tailnet_key" "ec2_join" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  description   = "${var.project} EC2 join key"
}

# Bastion 기기 대기 → 광고한 VPC 라우트 자동 승인
data "tailscale_device" "bastion" {
  hostname   = "${var.project}-bastion"
  wait_for   = "180s"
  depends_on = [aws_instance.bastion]
}

resource "tailscale_device_subnet_routes" "bastion" {
  device_id = data.tailscale_device.bastion.id
  routes    = [var.vpc_cidr]
}

# DB 기기 대기 (복제용 100.x IP 확보 → outputs 로 노출)
data "tailscale_device" "db" {
  hostname   = "${var.project}-db"
  wait_for   = "180s"
  depends_on = [aws_instance.db]
}