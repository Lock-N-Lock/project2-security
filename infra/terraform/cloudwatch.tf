# =============================================================
# cloudwatch.tf — CloudWatch 알람 + ASG Scale Out + SNS
#  멘토 피드백: 모니터링에 CloudWatch 도입 (AWS 인프라 계층)
#  시나리오3(트래픽 폭주) → CPU TargetTracking 자동 확장
#  ALB 5xx / UnHealthyHost → SNS (D 트랙 알림 연동점)
# 파일위치 : ~/project2-security/infra/terraform/cloudwatch.tf
# =============================================================

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# ── ASG Scale Out : CPU 60% Target Tracking ───────────────
resource "aws_autoscaling_policy" "app_cpu" {
  name                   = "${var.project}-app-cpu-tt"
  autoscaling_group_name = aws_autoscaling_group.blue.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

# ── ALB 5xx 급증 (서비스 장애 의심) ───────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { LoadBalancer = aws_lb.web_alb.arn_suffix }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# ── Target Group Unhealthy (앱 인스턴스 다운) ─────────────
# NOTE(2026-06-19):
# BankAppDown(Prometheus) + Recovery Controller가 서비스 레벨 장애를 감지/복구하므로,
# Target Group UnHealthyHostCount 알람은 동일 장애에 대한 중복 알림과 불필요한 비용을 유발한다.
# ASG의 ELB Health Check 기반 인스턴스 교체는 이 CloudWatch Alarm 없이도 동작한다.
# 장기 장애 감지 용도로 필요할 경우 count를 1로 변경하여 재활성화한다.
resource "aws_cloudwatch_metric_alarm" "tg_unhealthy" {
  count               = 0
  alarm_name          = "${var.project}-tg-unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    LoadBalancer = aws_lb.web_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.blue.arn_suffix
  }
  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "tg_unhealthy_green" {
  count               = 0
  alarm_name          = "${var.project}-tg-unhealthy-green"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    LoadBalancer = aws_lb.web_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.green.arn_suffix
  }
  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# 트래픽 폭주 시 Green ASG 오토스케일링 정책 추가
# 목적: [시나리오 3 & 7] 배포 전환이 완료되어 운영망이 Green이 되었을 때, 
# Locust 트래픽 폭주가 발생해도 정상적으로 Scale-Out이 트리거되도록 보장합니다.
resource "aws_autoscaling_policy" "app_cpu_green" {
  name                   = "${var.project}-app-cpu-tt-green"
  autoscaling_group_name = aws_autoscaling_group.green.name # ◀ Green ASG 결합
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}