locals {
  ecs_container_definitions = [
    {
      image       = var.image_name
      name        = "${var.env_name}-${var.app_name}",
      networkMode = "awcvpc",

      portMappings = [
        {
          containerPort = var.container_port,
          hostPort      = var.container_port
        }
      ]

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.fargate.name}",
          awslogs-region        = "${var.region}",
          awslogs-stream-prefix = "ecs"
        }
      }

      environment = var.environment
    }
  ]

  https       = var.https_enabled == true
  nat_enabled = var.use_nat == true
}

# Reference resources
data "aws_availability_zones" "available" {
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

##############################
# Network Interfaces
##############################

# Security group for public subnet holding load balancer
resource "aws_security_group" "alb" {
  name        = "${var.env_name}-${var.app_name}-alb"
  description = "Allow access on port 443 only to ALB"
  vpc_id      = data.aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }
}

# Allow ingress rule appropriate to HTTP Protocol used
resource "aws_security_group_rule" "tcp_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}


resource "aws_security_group_rule" "tcp_80" {
  count = local.https ? 0 : 1

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# Public subnet for ALB
resource "aws_subnet" "fargate_public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, var.cidr_bit_offset + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = data.aws_vpc.vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env_name} ${var.app_name} #${var.az_count + count.index} (public)"
  }
}

# Private subnet to hold fargate container
resource "aws_subnet" "fargate_ecs" {
  count             = var.az_count
  cidr_block        = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, var.cidr_bit_offset + var.az_count + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = data.aws_vpc.vpc.id

  tags = {
    Name = "${var.env_name} ${var.app_name} #${count.index} (private)"
  }
}

# Private subnet for the ECS - only allows access from the ALB
resource "aws_security_group" "fargate_ecs" {
  name        = "${var.env_name}-${var.app_name}-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = var.container_port
    to_port         = var.container_port
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }
}

##############################
# Load Balancer
##############################

resource "aws_alb" "fargate" {
  count           = local.nat_enabled ? 0 : 1
  name            = "${var.env_name}-${var.app_name}-alb"
  subnets         = aws_subnet.fargate_public.*.id
  security_groups = [aws_security_group.alb.id]

  access_logs {
    bucket  = aws_s3_bucket.fargate.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket.fargate]
}

resource "aws_alb_target_group" "fargate" {
  count       = local.nat_enabled ? 0 : 1
  name        = "${var.env_name}-${var.app_name}-alb-tg2"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.vpc.id
  target_type = "ip"
}

resource "aws_alb_listener" "fargate" {
  count             = local.nat_enabled ? 0 : 1
  load_balancer_arn = aws_alb.fargate[count.index].id
  port              = local.https ? "443" : "80"
  protocol          = local.https ? "HTTPS" : "HTTP"
  certificate_arn   = local.https ? var.cert_arn : ""

  default_action {
    target_group_arn = aws_alb_target_group.fargate[count.index].id
    type             = "forward"
  }
}

##############################
# NAT Gateway
##############################

resource "aws_eip" "ip" {
  count = local.nat_enabled ? var.az_count : 0
  vpc   = true

  tags = {
    Name = "IP NAT Gateway ${var.env_name}-${var.app_name}"
  }
}

resource "aws_nat_gateway" "gw" {
  count         = local.nat_enabled ? var.az_count : 0
  allocation_id = aws_eip.ip[count.index].id
  subnet_id     = aws_subnet.fargate_public[count.index].id

  tags = {
    Name = "NAT Gateway ${var.env_name}-${var.app_name}"
  }
}

##############################
# ECS
##############################
resource "aws_ecs_task_definition" "fargate" {
  family                   = var.task_group_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu_units
  memory                   = var.ram_units
  execution_role_arn       = aws_iam_role.fargate_role.arn
  task_role_arn            = aws_iam_role.fargate_role.arn

  container_definitions = jsonencode(local.ecs_container_definitions)
}

resource "aws_ecs_cluster" "fargate" {
  name = "${var.env_name}-${var.app_name}-cluster"
}

resource "aws_ecs_service" "fargate" {
  depends_on = [
    aws_ecs_task_definition.fargate,
    aws_cloudwatch_log_group.fargate,
    aws_alb_listener.fargate,
    aws_alb_target_group.fargate,
    aws_alb.fargate
  ]
  name            = "${var.env_name}-${var.app_name}-service"
  cluster         = aws_ecs_cluster.fargate.id
  task_definition = aws_ecs_task_definition.fargate.arn
  desired_count   = var.az_count
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.fargate_ecs.id]
    subnets          = aws_subnet.fargate_ecs.*.id
  }

  dynamic "load_balancer" {
    for_each = local.nat_enabled ? [] : list(1)

    content {
      target_group_arn = aws_alb_target_group.fargate.id
      container_name   = "${var.env_name}-${var.app_name}"
      container_port   = var.container_port
    }
  }
}
