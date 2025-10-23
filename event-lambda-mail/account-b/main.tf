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

resource "aws_ssm_parameter" "smtp_auth_code" {
  name  = "/lambda/mail/smtp_auth_code"
  type  = "SecureString"
  value = "SBTLHpimp4ZWSZbW"   # 建议用 terraform.tfvars 或 CI/CD 注入
}

# 从 SSM Parameter Store 读取授权码
data "aws_ssm_parameter" "smtp_auth_code" {
  depends_on = [aws_ssm_parameter.smtp_auth_code]
  name = "/lambda/mail/smtp_auth_code"   # 这里要和你在 SSM 里保存的参数名一致
}



data "archive_file" "mail_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda-mail.py"
  output_path = "${path.module}/lambda/lambda-mail.py.zip"
}

resource "aws_lambda_function" "mail_lambda" {
  function_name = "mail_lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler = "lambda-mail.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.mail_lambda_zip.output_path
  source_code_hash = data.archive_file.mail_lambda_zip.output_base64sha256
  timeout       = 30

  environment {
    variables = {
      SMTP_SERVER     = "smtp.yeah.net"
      SMTP_PORT       = "465"
      SENDER_EMAIL    = "lb6476@yeah.net"
      RECIPIENT_EMAIL = "1613213150@qq.com"
      # SMTP_AUTH_CODE  = data.aws_ssm_parameter.smtp_auth_code.value
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "mail_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "mail_lambda_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 允许写 CloudWatch Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # 允许 Lambda 读取 SSM 参数
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter"
        ],
        Resource = "arn:aws:ssm:us-east-1:496390993498:parameter/lambda/mail/smtp_auth_code"
      },
      # 如果参数是 SecureString，还需要解密权限
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt"
        ],
        Resource = "*" # 可以收紧到具体的 KMS key ARN
      }
    ]
  })
}
