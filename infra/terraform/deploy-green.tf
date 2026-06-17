#
#
#

resource "null_resource" "deploy_app_to_green" {
  depends_on = [
    aws_autoscaling_group.green
  ]

  triggers = {
    green_desired_capacity = aws_autoscaling_group.green.desired_capacity
    app_image              = var.app_image
    force_run              = timestamp()
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/../.. && make deploy-app-green"
  }
}