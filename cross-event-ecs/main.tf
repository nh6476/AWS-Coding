terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}

provider "aws" {
  alias   = "account_a"
  region  = "us-east-1"
  profile = "account-a"
}

provider "aws" {
  alias   = "account_b"
  region  = "us-east-1"
  profile = "account-b"
}

data "aws_caller_identity" "a" {
  provider = aws.account_a
}

# 获取 B 账户信息
data "aws_caller_identity" "b" {
  provider = aws.account_b
}

output account_a_id {
  value       = data.aws_caller_identity.a.account_id
  depends_on  = [data.aws_caller_identity.a]
}

output account_b_id {
  value       = data.aws_caller_identity.b.account_id
  depends_on  = [data.aws_caller_identity.b]
}

########################################################################



resource "aws_vpc" "main" {
  provider            = aws.account_b
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}


resource "aws_internet_gateway" "igw" {
  provider  = aws.account_b 
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public_a" {
  provider                = aws.account_b 
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  provider                = aws.account_b
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_route_table" "public" {
  provider  = aws.account_b 
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "default_route" {
  provider  = aws.account_b 
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  provider  = aws.account_b
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  provider  = aws.account_b
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


resource "aws_security_group" "ecs_tasks" {
  provider    = aws.account_b
  name        = "ecs-tasks-sg"
  description = "Allow all inbound and outbound traffic for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-tasks-sg"
  }
}

# resource "aws_ecs_service" "send_env_mail_service" {
#   provider  = aws.account_b
#   name            = "send-env-mail-service"
#   cluster         = aws_ecs_cluster.default.id
#   task_definition = aws_ecs_task_definition.send_env_mail.arn
#   launch_type     = "FARGATE"
#   desired_count   = 1

#   network_configuration {
#     subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
#     security_groups = [aws_security_group.ecs_tasks.id]
#     assign_public_ip = true  # 如果你需要公网访问可设为 true
#   }

#   deployment_controller {
#     type = "ECS"
#   }

#   enable_execute_command = true

#   depends_on = [
#     aws_iam_role.task_execution,
#     aws_iam_role.task_role
#   ]
# }


resource "aws_ecs_cluster" "default" {
  provider  = aws.account_b
  name = "send-env-mail-cluster"

  tags = {
    Environment = "prod"
    Service     = "send-env-mail"
  }
}


resource "aws_ssm_parameter" "smtp_auth_code" {
  provider    = aws.account_b
  name        = "/lambda/mail/smtp_auth_code"
  type        = "SecureString"
  value       = "MPWucraJyRXHVYXh"  # 建议用变量或 secrets 管理
  description = "SMTP auth code for send-env-mail container"
  tags = {
    Environment = "prod"
    Service     = "send-env-mail"
  }
}






resource "aws_cloudwatch_log_group" "ecs_log_group" {
  provider  = aws.account_b
  name              = "/ecs/send-env-mail"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "send_env_mail" {
  provider                  = aws.account_b
  family                   = "SendEnvMailTask"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "send-env-mail",
      image     = "nh6476/send-env-mail:latest",
      essential = true,
      environment = [
        { name = "SMTP_SERVER",     value = "smtp.yeah.net" },
        { name = "SMTP_PORT",       value = "465" },
        { name = "SENDER_EMAIL",    value = "lb6476@yeah.net" },
        { name = "RECIPIENT_EMAIL", value = "1613213150@qq.com" },
        { name = "AWS_REGION",      value = "us-east-1" },
        # { name = "SMTP_AUTH_CODE",  value = "MPWucraJyRXHVYXh" }
      ],
      secrets = [
        {
          name      = "SMTP_AUTH_CODE",
          valueFrom = aws_ssm_parameter.smtp_auth_code.arn
          # 或者使用 Secrets Manager：
          # valueFrom = aws_secretsmanager_secret.smtp_auth_code.arn
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-region        = "us-east-1",
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}





resource "aws_iam_role" "task_execution" {
  provider  = aws.account_b
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_policy" {
  provider  = aws.account_b
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_iam_role" "task_role" {
  provider  = aws.account_b 
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_policy" "ssm_kms_policy" {
  provider    = aws.account_b
  name        = "ssm_kms_policy"
  description = "Allow ECS task code to read SSM parameters under /lambda/mail path"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = "arn:aws:ssm:us-east-1:496390993498:parameter/lambda/mail/*"
      },
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = "arn:aws:kms:us-east-1:496390993498:alias/aws/ssm"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_ssm_attach" {
  provider  = aws.account_b
  role       = aws_iam_role.task_role.name   # ✅ 附加到 task_role
  policy_arn = aws_iam_policy.ssm_kms_policy.arn
}



resource "aws_iam_role_policy_attachment" "execute_role_ssm_attach" {
  provider  = aws.account_b
  role       = aws_iam_role.task_execution.name   # ✅ 附加到 task_execution
  policy_arn = aws_iam_policy.ssm_kms_policy.arn
}




########################################################################


