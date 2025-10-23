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
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:StartInstances"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "*"
      }
    ]
  })
}

# resource "aws_cloudwatch_event_bus" "custom_bus" {
#   name = "ec2-events-bus"
# }

# resource "aws_cloudwatch_event_rule" "ec2_all_events" {
#   name           = "forward-all-ec2-events"
#   description    = "Forward all EC2 events to Lambda"
#   event_bus_name = aws_cloudwatch_event_bus.custom_bus.nacdme
#   event_pattern  = jsonencode({
#     "source": ["aws.ec2"]
#   })
# }

resource "aws_cloudwatch_event_rule" "ec2_all_events" {
  name        = "forward-all-ec2-events"
  description = "Forward EC2 events to Lambda"
  event_pattern = jsonencode({
    "source": ["aws.ec2"]
  })
  # 不指定 event_bus_name，默认就是 default
}


resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule           = aws_cloudwatch_event_rule.ec2_all_events.name
  target_id      = "event-log-lambda"
  arn            = aws_lambda_function.event_log_lambda.arn
}


resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_log_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_all_events.arn
}

#############################################################

resource "aws_cloudwatch_event_rule" "forward_to_a_bus" {
  name        = "forward-to-a-custom-bus"
  description = "Forward EC2 events to A account's custom bus"
  event_pattern = jsonencode({
    "source": ["aws.ec2"]
  })
  # 默认事件总线，不指定 event_bus_name
}


resource "aws_iam_role" "eventbridge_forwarder" {
  name = "eventbridge-forwarder-role"
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

resource "aws_iam_policy" "forward_policy" {
  name   = "eventbridge-forward-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "events:PutEvents",
      Resource = "arn:aws:events:us-east-1:708365820815:event-bus/ec2-events-bus"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_forward_policy" {
  role       = aws_iam_role.eventbridge_forwarder.name
  policy_arn = aws_iam_policy.forward_policy.arn
}


resource "aws_cloudwatch_event_target" "send_to_a_bus" {
  rule      = aws_cloudwatch_event_rule.forward_to_a_bus.name
  arn       = "arn:aws:events:us-east-1:708365820815:event-bus/ec2-events-bus"
  role_arn  = aws_iam_role.eventbridge_forwarder.arn
  target_id = "send-to-a-custom-bus"
}


########################################

resource "aws_iam_role" "ec2_starter_for_a" {
  name = "ec2-starter-for-a"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        AWS = "arn:aws:iam::708365820815:root"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "start_ec2_policy" {
  name = "start-ec2-policy"
  role = aws_iam_role.ec2_starter_for_a.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:StartInstances",
          "ec2:DescribeInstances"  # ✅ 建议添加：用于 Lambda 验证权限
        ],
        Resource = "*"
      }
    ]
  })
}
