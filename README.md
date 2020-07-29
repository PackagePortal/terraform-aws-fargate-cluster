# AWS Fargate Cluster

This module works for terraform 0.12.x, there is no terraform 0.11.x support.

Terraform module that creates the following to make a fargate cluster:

- ECS Cluster
- ECS Task defintion
- Cloudwatch logs
- IAM Permissions to: 
   - Log to Cloudwatch logs/S3
   - Assume its own role
- ALB Load Balancer
- Public subnet for load balancer
- Private subnet for ECS Cluster (only acessible via load balancer)

**Note**: Out of the box this module will not work for https without a provided cert. It
will also need additional permissions to access any other AWS services.

## Usage

Below is some example code using this module:

```
module "fargate" {
  source  = "PackagePortal/fargate-cluster/aws"
  version = "0.0.3"

  region            = "us-west-1"
  app_name          = "test-app"
  az_count          = 2
  vpc_id            = var.vpc_id  # This can be passed in as a variable or come from a resource attribute
  image_name        = "image_name"
  cpu_units         = 256
  ram_units         = 512
  task_group_family = "test-task-family"
  cidr_bit_offset   = 8
  container_port    = 3000
  https_enabled     = true
  environment       = [
    {
      name: "FOO"
      value: "BAR"
    }
  ]
  env_name          = local.env
  cert_arn          = aws_acm_certificate.cert.arn
}
```

If you want to run with a NAT Gateway instead of a load balancer, set `use_nat` to `true`.
This will create a NAT Gateway in each public subnet instead of a load balancer.

### Using with ECR:

If you are using Amazon ECR to host custom docker images, you will need to add the following IAM permissions.
Without these, the image cannot be pulled to your Fargate task:

```
data "aws_iam_policy_document" "ecr_image_pull" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]

    resources = [
      "*", # This needs to be a wildcard so that the GetAuthorizationToken permission is granted
    ]
  }
}

resource "aws_iam_policy" "ecr_image_pull" {
  name        = "${local.env}-${local.name-base}-ecr"
  path        = "/"
  description = "Allow Fargate to interact with ECR"

  policy = data.aws_iam_policy_document.ecr_image_pull.json
}

resource "aws_iam_role_policy_attachment" "fargate_ecr" {
  role       = module.fargate.iam_role.name
  policy_arn = aws_iam_policy.ecr_image_pull.arn
}
```

To acess these without going to the public internet, VPC Endpoints can be added.

See [here](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html)
for what services can be endpoints, an example is below:

```
resource "aws_vpc_endpoint" "example_endpoint" {
  count = var.az_count

  vpc_id = data.aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    module.fargate.private_security_group_id,
  ]

  subnet_ids = [
    module.fargate.private_subnets[count.index].id,
  ]
}
```
