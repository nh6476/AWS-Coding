terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  profile  = "account-b"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/event_log.py"
  output_path = "${path.module}/lambda/event_log.zip"
}

resource "aws_lambda_function" "event_log_lambda" {
  function_name = "event_log_lambda"
  role          = aws_iam_role.lambda_exec.arn
  handler = "event_log.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout = 15  # ✅ 设置为 15 秒，根据你的逻辑建议 ≥10 秒
}


resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:StartInstances"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "sts:AssumeRole"
        ],
        Resource = "arn:aws:iam::496390993498:role/ec2-starter-for-a"
      }
    ]
  })
}


resource "aws_cloudwatch_event_bus" "custom_bus" {
  name = "ec2-events-bus"
}

output  custom_bus_arn{
  value       = aws_cloudwatch_event_bus.custom_bus.arn
}

resource "aws_cloudwatch_event_permission" "allow_A_account" {
  principal       = "708365820815"
  statement_id    = "AllowBAccountToPutEvents"
  action          = "events:PutEvents"
  event_bus_name  = aws_cloudwatch_event_bus.custom_bus.name
}


resource "aws_cloudwatch_event_rule" "receive_from_A" {
  name           = "receive-from-A"
  description    = "接收从 A 账户转发的事件"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name  
  event_pattern  = jsonencode({
    "source": ["aws.ec2"]
  })
}

resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule           = aws_cloudwatch_event_rule.receive_from_A.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "event-log-lambda"
  arn            = aws_lambda_function.event_log_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_log_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.receive_from_A.arn
}

##################################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_tasks" {
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

resource "aws_ecs_cluster" "default" {
  name = "send-env-mail-cluster"

  tags = {
    Environment = "prod"
    Service     = "send-env-mail"
  }
}


resource "aws_ssm_parameter" "smtp_auth_code" {
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
  name              = "/ecs/send-env-mail"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "send_env_mail" {
  family                   = "SendEnvMailTask"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
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

resource "aws_iam_role" "ecs_task_execution" {
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
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
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
  role       = aws_iam_role.task_role.name   # ✅ 附加到 task_role
  policy_arn = aws_iam_policy.ssm_kms_policy.arn
}



resource "aws_iam_role_policy_attachment" "execute_role_ssm_attach" {
  role       = aws_iam_role.ecs_task_execution.name   # ✅ 附加到 task_execution
  policy_arn = aws_iam_policy.ssm_kms_policy.arn
}

########################################################################


# resource "aws_ecs_service" "send_env_mail_service" {
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
#     aws_iam_role.ecs_task_execution,
#     aws_iam_role.task_role
#   ]
# }

resource "aws_cloudwatch_event_target" "ecs_target" {
  rule      = aws_cloudwatch_event_rule.receive_from_A.name
  target_id = "ecs-task-target"
  arn       = aws_ecs_cluster.default.arn
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.send_env_mail.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = true
    }
  }

  role_arn = aws_iam_role.eventbridge_invoke_ecs.arn
  input_transformer {
    input_paths = {
      detail_type = "$.detail-type"
      instance_id = "$.detail.instance-id"
      state       = "$.detail.state"
    }

  input_template = <<EOF
  {
    "containerOverrides": [
      {
        "name": "send-env-mail",
        "environment": [
          { "name": "EVENT_DETAIL_TYPE", "value": "<detail_type>" },
          { "name": "INSTANCE_ID",       "value": "<instance_id>" },
          { "name": "INSTANCE_STATE",    "value": "<state>" }
        ]
      }
    ]
  }
  EOF
  }
}

resource "aws_iam_role" "eventbridge_invoke_ecs" {
  name = "eventbridge-ecs-invoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "events.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_invoke_policy" {
  name = "ecs-invoke-policy"
  role = aws_iam_role.eventbridge_invoke_ecs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:RunTask",
          "iam:PassRole"
        ],
        Resource = "*"
      }
    ]
  })
}