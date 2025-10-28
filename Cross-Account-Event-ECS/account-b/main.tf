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
  event_bus_name  = "ec2-events-bus"
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

# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_support   = true
#   enable_dns_hostnames = true
#   tags = {
#     Name = "main-vpc"
#   }
# }

# resource "aws_internet_gateway" "igw" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "main-igw"
#   }
# }

# resource "aws_subnet" "public_a" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.1.0/24"
#   availability_zone       = "us-east-1a"
#   map_public_ip_on_launch = true
#   tags = {
#     Name = "public-subnet-a"
#   }
# }

# resource "aws_subnet" "public_b" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.2.0/24"
#   availability_zone       = "us-east-1b"
#   map_public_ip_on_launch = true
#   tags = {
#     Name = "public-subnet-b"
#   }
# }

# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "public-route-table"
#   }
# }

# resource "aws_route" "default_route" {
#   route_table_id         = aws_route_table.public.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.igw.id
# }

# resource "aws_route_table_association" "public_a" {
#   subnet_id      = aws_subnet.public_a.id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_route_table_association" "public_b" {
#   subnet_id      = aws_subnet.public_b.id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_security_group" "ecs_tasks" {
#   name        = "ecs-tasks-sg"
#   description = "Allow all inbound and outbound traffic for ECS tasks"
#   vpc_id      = aws_vpc.main.id

#   ingress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "ecs-tasks-sg"
#   }
# }