#########################################
# Create linked service role
# 
# This is safe to leave as false,
# unless this role has never been created
# in your AWS account.
##########################################
resource "aws_iam_service_linked_role" "ecs_service" {
  aws_service_name = "ecs.amazonaws.com"
  count            = var.create_iam_service_linked_role ? 1 : 0

  lifecycle {
    prevent_destroy = true
  }
}

##########################################
# Allow ALB to log to S3 Bucket
##########################################

data "aws_elb_service_account" "main" {
}

data "aws_iam_policy_document" "fargate" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.fargate.arn}/alb/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "fargate" {
  bucket = aws_s3_bucket.fargate.id
  policy = data.aws_iam_policy_document.fargate.json
}

##########################################
# Allow Fargate to publish to logs
##########################################

data "aws_iam_policy_document" "log_publishing" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
    ]

    resources = ["arn:aws:logs:${var.region}:*:log-group:/ecs/${var.env_name}-${var.app_name}:*"]
  }
}

resource "aws_iam_policy" "fargate_log_publishing" {
  name        = "${var.env_name}-${var.app_name}-log-pub"
  path        = "/"
  description = "Allow publishing to cloudwach"

  policy = data.aws_iam_policy_document.log_publishing.json
}

data "aws_iam_policy_document" "fargate_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fargate_role" {
  name               = "${var.env_name}-${var.app_name}-role"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "fargate_role_log_publishing" {
  role       = aws_iam_role.fargate_role.name
  policy_arn = aws_iam_policy.fargate_log_publishing.arn
}
