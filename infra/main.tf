# Do not edit below unless you know what you're doing

# The ECR repository is created as a resource because a dedicated
# local module for it was not found in the specified directory.
resource "aws_ecr_repository" "app" {
  name = var.app_name
}

module "vpc" {
  source  = "Senora-dev/vpc/aws"
  version = "~> 1.0"

  name     = "${var.app_name}-vpc"
  vpc_cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

module "alb_sg" {
  source  = "Senora-dev/security-group/aws"
  version = "~> 1.0"

  name   = "app-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Allow HTTP inbound from anywhere"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Name = "app-alb-sg"
  }
}

module "app_sg" {
  source  = "Senora-dev/security-group/aws"
  version = "~> 1.0"

  name   = "app-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Allow HTTP from anywhere"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Name = "app-sg"
  }
}

module "alb" {
  source  = "Senora-dev/load-balancer/aws"
  version = "~> 1.0"

  name            = "alb1"
  use_name_prefix = false

  load_balancer_type = "application"
  internal           = false
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]

  target_groups = {
    main = {
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
      port             = 80
      protocol         = "HTTP"
    }
  }

  listeners = {
    http = {
      protocol = "HTTP"
      port     = 80
      default_action = {
        type             = "forward"
        target_group_arn = module.alb.target_groups["main"].arn
      }
    }
  }

  tags = {
    Name = "alb1"
  }
}

module "ecs_task_execution_role" {
  source  = "Senora-dev/iam-role/aws"
  version = "~> 1.0"

  name               = "app-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
  use_name_prefix    = false

  managed_policy_arns = {
    AmazonECSTaskExecutionRolePolicy = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  }

  tags = {
    Name = "app-exec"
  }
}

module "ecs" {
  source  = "Senora-dev/ecs/aws"
  version = "~> 1.0"

  cluster_name = "app-cluster"

  task_family              = "app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  task_cpu                 = 256
  task_memory              = 512
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn

  container_definitions = [
    {
      name      = var.app_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ]

  service_name = "app-service2"
  launch_type  = "FARGATE"

  network_configuration = {
    subnets          = module.vpc.private_subnets
    security_groups  = [module.app_sg.security_group_id]
    assign_public_ip = false
  }

  load_balancer = {
    target_group_arn = module.alb.target_groups["main"].arn
    container_name   = var.app_name
    container_port   = 80
  }

  desired_count = 1

  tags = {
    Name = "app-ecs"
  }
} 