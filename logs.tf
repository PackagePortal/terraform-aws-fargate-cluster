# Cloudwatch log group and S3 Bucket to store logs from the service
resource "aws_cloudwatch_log_group" "fargate" {
  name = "/ecs/${var.env_name}-${var.app_name}"
}

resource "aws_s3_bucket" "fargate" {
  bucket        = "${var.region}-${var.app_name}-alb-logs"
  acl           = "private"
  force_destroy = "true"
}
