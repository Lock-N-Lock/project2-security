# =============================================================
# compute.tf — NAT instance / Bastion / App ASG(Blue·Green) / DB
# AMI: Amazon Linux 2023 (SSM 파라미터로 최신 조회)
# Bastion = Tailscale 서브넷 라우터, App = Swarm 노드
# 파일위치 : ~/project2-security/infra/terraform/compute.tf
# =============================================================

# ── 최신 AMI (Amazon Linux 2023) ──────────────────────────
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── NAT instance (비용 절감: NAT GW 대신 t3.micro) ────────
resource "aws_instance" "nat" {
  ami                         = data.aws_ssm_parameter.al2023.value # AL2023 재사용
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  associate_public_ip_address = true
  source_dest_check           = false
  key_name                    = var.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf
    dnf install -y iptables iptables-services
    systemctl enable --now iptables
    iptables -P FORWARD ACCEPT
    iptables -I FORWARD -j ACCEPT
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables
  EOF

  tags = { Name = "${var.project}-nat" }
}

# 프라이빗(App) 0.0.0.0/0 → NAT instance
resource "aws_route" "app_nat" {
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# 프라이빗(DB) 0.0.0.0/0 → NAT instance (egress-only)
resource "aws_route" "db_nat" {
  route_table_id         = aws_route_table.private_db.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# =============================================================
# compute.tf 파일 내부의 Bastion 블록 교체본
# =============================================================

# ── Bastion (public, Tailscale 서브넷 라우터) ─────────────
resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  source_dest_check           = false # ← 서브넷 라우터 가동을 위한 필수 설정

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/user_data_tailscale.log) 2>&1
    hostnamectl set-hostname "${var.project}-bastion"
    
    # 외부망 통신 대기
    until ping -c 1 8.8.8.8 &> /dev/null; do sleep 5; done
    
    # Tailscale 설치 및 서비스 가동
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    
    # IP 포워딩 활성화 (서브넷 라우팅 필수 커널 파라미터)
    cat <<EOT > /etc/sysctl.d/99-tailscale.conf
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
    EOT
    sysctl -p /etc/sysctl.d/99-tailscale.conf
    
    # Tailscale 가상망 조인 및 AWS VPC 라우트 광고
    tailscale up --authkey=${tailscale_tailnet_key.ec2_join.key} \
      --advertise-routes=${var.vpc_cidr} --accept-routes \
      --hostname=${var.project}-bastion
      
    # Docker Engine 기본 설치
    dnf install -y docker && systemctl enable --now docker
  EOF

  tags = { Name = "${var.project}-bastion" }
}

# ── App Launch Template (Blue/Green 공용 베이스) ──────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-app-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.app_instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.app.id]

  # 최소 부트스트랩(Docker). 앱 배포·Swarm join 은 B/C 트랙이 Ansible/Actions 로 수행.
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
    USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── App ASG : Blue ────────────────────────────────────────
resource "aws_autoscaling_group" "blue" {
  name                      = "${var.project}-asg-blue"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_desired
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.blue.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90 # ← 이 줄 추가 (교체 인스턴스 부팅 여유, 데모용 90s)

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Color"
    value               = "blue"
    propagate_at_launch = true
  }

  depends_on = [aws_route.app_nat]
}

# ── App ASG : Green (초기 desired=0, 전환 시 확장) ────────
resource "aws_autoscaling_group" "green" {
  name                      = "${var.project}-asg-green"
  min_size                  = 0
  max_size                  = var.asg_max
  desired_capacity          = 0
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.green.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90 # ◀ 이 줄을 추가하여 초기 컨테이너 구동 시간 확보
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Color"
    value               = "green"
    propagate_at_launch = true
  }

  depends_on = [aws_route.app_nat]
}

# ── DB EC2 (PostgreSQL 컨테이너 호스트) ───────────────────
resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.db[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.db.name

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/user_data_tailscale.log) 2>&1
    hostnamectl set-hostname "${var.project}-db"
    until ping -c 1 8.8.8.8 &> /dev/null; do sleep 5; done
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    tailscale up --authkey=${tailscale_tailnet_key.ec2_join.key} \
      --accept-routes=false --hostname=${var.project}-db
    dnf install -y docker && systemctl enable --now docker
  EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project}-db" }

  depends_on = [aws_route.db_nat]
}