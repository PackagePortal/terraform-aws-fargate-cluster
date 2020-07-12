output "private_subnets" {
  description = "List of private subnets (on the ECS service hosting fargate)."
  value = aws_subnet.fargate_ecs
}

output "public_subnets" {
  description = "List of public subnets (on the load balancer)."
  value = aws_subnet.fargate_public
}

output "iam_role" {
  description = "IAM role for the fargate cluster. Can be used to link additional IAM permissions."
  value = aws_iam_role.fargate_role
}

output "public_security_group_id" {
  description = "Id of the public security group (containing ALB)."
  value = aws_security_group.alb.id
}

output "private_security_group_id" {
  description = "Id of the private security group (containing ECS Cluster)."
  value = aws_security_group.fargate_ecs.id
}
