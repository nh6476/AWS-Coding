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

###########################################################



# 创建 S3 桶用于存储配置快照
resource "aws_s3_bucket" "config_bucket" {
  bucket = "nk-config-bucket-123456"  # 替换为唯一名称
}

# 创建 IAM 角色供 AWS Config 使用
resource "aws_iam_role" "config_role" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "config.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM 角色策略：允许写入 S3、CloudWatch Logs 等
# resource "aws_iam_role_policy" "config_policy" {
#   role = aws_iam_role.config_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "s3:PutObject",
#           "s3:GetBucketAcl",
#           "s3:ListBucket"
#         ],
#         Resource = [
#           "${aws_s3_bucket.config_bucket.arn}",
#           "${aws_s3_bucket.config_bucket.arn}/*"
#         ]
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "config:Put*",
#           "config:Get*",
#           "config:Describe*",
#           "cloudwatch:PutMetricData"
#         ],
#         Resource = "*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "ec2:DescribeInstances",
#           "ec2:DescribeTags"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

resource "aws_iam_role_policy_attachment" "config_admin_access" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# 创建配置记录器
resource "aws_config_configuration_recorder" "recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resource_types = true
  }
}

# 创建交付通道
resource "aws_config_delivery_channel" "channel" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
}

# 启动配置记录器（必须依赖交付通道）
resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.recorder.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.channel]
}


###########################################################

data "archive_file" "lambda_zip" {import smtplib
import json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# 邮箱配置
smtp_server = 'smtp.163.com'
smtp_port = 465
sender_email = 'xxx@yeah.net'         # 替换为你的 yeah.net 邮箱
recipient_email = 'your_target@email.com'  # 收件人邮箱
auth_code = '你的授权码'               # 替换为你获取的授权码

def lambda_handler(event, context):
    event_body = json.dumps(event, indent=2)

    message = MIMEMultipart()
    message['From'] = sender_email
    message['To'] = recipient_email
    message['Subject'] = 'Lambda Event Notification'
    message.attach(MIMEText(event_body, 'plain'))

    try:
        with smtplib.SMTP_SSL(smtp_server, smtp_port) as server:
            server.login(sender_email, auth_code)
            server.sendmail(sender_email, recipient_email, message.as_string())
        return {'statusCode': 200, 'body': '邮件发送成功'}
    except Exception as e:
        return {'statusCode': 500, 'body': f'邮件发送失败: {str(e)}'}



############################################################

resource "aws_config_config_rule" "ec2_env_tag_check" {
  name = "ec2-env-tag-check"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.config-rule-ec2tag.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }

    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [aws_lambda_function.config-rule-ec2tag]
}


resource "aws_lambda_permission" "allow_config_invoke" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config-rule-ec2tag.function_name
  principal     = "config.amazonaws.com"
  source_account = 496390993498
}

#⚠️ 注意：如果你使用的是 cross-account Config 规则，还需要设置 source_arn 来限制调用来源。


########################################################


# ---------------------------
# 1. SSM Automation Document
# ---------------------------

# 2. 创建 SSM Automation 文档
# resource "aws_ssm_document" "set_env_from_owner_direct" {
#   name            = "SetEnvTagFromOwnerOrDefault-Direct"
#   document_type   = "Automation"
#   document_format = "YAML"

#   content = <<DOC
# ---
# schemaVersion: '0.3'
# description: "使用 boto3 读取实例的 owner 标签并设置 env 标签为相同值，如果没有则设为 DEV"
# assumeRole: "{{ AutomationAssumeRole }}"
# parameters:
#   InstanceId:
#     type: String
#     description: "EC2 实例 ID"
#   AutomationAssumeRole:
#     type: String
#     description: "执行 Automation 的 IAM Role ARN"

# mainSteps:
#   - name: ExtractOwner
#     action: aws:executeScript
#     inputs:
#       InputPayload:
#         InstanceId: "{{ InstanceId }}"
#         xxxx: "debug"
#         yyyy: "debug"
#       Runtime: python3.6
#       Handler: extract_owner
#       Script: |
#         import boto3

#         def extract_owner(event, context):
#             print("DEBUG - Input Event:", event)
#             ec2 = boto3.client('ec2')
#             instance_id = event.get("InstanceId")
#             print("DEBUG - Instance ID:", instance_id)
#             response = ec2.describe_instances(InstanceIds=[instance_id])
#             print("DEBUG - Raw Response:", response)
#             tags = []
#             for r in response.get("Reservations", []):
#                 for inst in r.get("Instances", []):
#                     tags.extend(inst.get("Tags", []))
#             print("DEBUG - Extracted Tags:", tags)
#   #           env_value = "DEV"
#   #           for t in tags:
#   #               if t.get("Key", "").lower() == "owner":
#   #                   env_value = t.get("Value")
#   #                   break
#   #           return {
#   #             "EnvValue": env_value,
#   #             "AllTags": tags
#   #           }

#   #   outputs:
#   #     - Name: EnvValue
#   #       Selector: "$.EnvValue"
#   #       Type: String
#   #     - Name: AllTags
#   #       Selector: "$.AllTags"
#   #       Type: StringMap

#   # - name: ApplyEnvTag
#   #   action: aws:createTags
#   #   inputs:
#   #     ResourceIds:
#   #       - "{{ InstanceId }}"
#   #     Tags:
#   #       - Key: "env"
#   #         Value: "{{ ExtractOwner.EnvValue }}"
# DOC
# }


# resource "null_resource" "run_ssm_automation" {
#   provisioner "local-exec" {
#     command = <<EOT
#       aws ssm start-automation-execution \
#         --document-name SetEnvTagFromOwnerOrDefault-Direct \
#         --parameters InstanceId=i-02432f840d9b4d5d2,AutomationAssumeRole=${aws_iam_role.ssm_automation_role.arn} \
#         --region us-east-1 \
#         --profile account-b
# EOT
#   }

#   triggers = {
#     always_run = "${timestamp()}"
#   }

# }


resource "aws_iam_role" "ssm_automation_role" {
  name = "SSM-Automation-ExecutionRole-xxx"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_automation_admin_attach" {
  role       = aws_iam_role.ssm_automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "ssm_automation_logging_policy" {
  name = "SSM-Automation-LoggingPolicy"
  role = aws_iam_role.ssm_automation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}
















######### ##################################
data "archive_file" "remediation-lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediation-ec2tag.py"
  output_path = "${path.module}/lambda/remediation-ec2tag.zip"
}

resource "aws_lambda_function" "remediation-ec2tag" {
  function_name = "remediation-ec2tag"
  role          = aws_iam_role.remediation-ec2tag.arn
  handler = "remediation-ec2tag.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.remediation-lambda_zip.output_path
  source_code_hash = data.archive_file.remediation-lambda_zip.output_base64sha256
  timeout = 20  # 设置为 10 秒，根据需要调整
}

resource "aws_iam_role" "remediation-ec2tag" {
  name = "remediation-ec2tag-role"

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


###########################################################


resource "aws_ssm_document" "invoke_lambda_direct" {
  name            = "InvokeLambdaFunction-Direct"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<DOC
---
schemaVersion: '0.3'
description: "通过 SSM Automation 调用 remediation-ec2tag Lambda 函数"
assumeRole: "{{ ExecutionRole }}"
parameters:
  InstanceId:
    type: String
    description: "目标 EC2 实例 ID"
  ExecutionRole:
    type: String
    description: "执行 Automation 的 IAM Role ARN"

mainSteps:
  - name: InvokeLambda
    action: aws:invokeLambdaFunction
    inputs:
      FunctionName: "${aws_lambda_function.remediation-ec2tag.function_name}"
      Payload: |
        {
          "instanceId": "{{ InstanceId }}"
        }
DOC
}

resource "aws_config_remediation_configuration" "ec2_env_tag_remediation" {
  config_rule_name               = aws_config_config_rule.ec2_env_tag_check.name
  target_type                    = "SSM_DOCUMENT"
  target_id                      = aws_ssm_document.invoke_lambda_direct.name
  automatic                      = false
  maximum_automatic_attempts     = 3  # 或更高，最大 25


  resource_type                  = "AWS::EC2::Instance"

  parameter {
    name           = "InstanceId"
    resource_value = "RESOURCE_ID"
  }

  parameter {
    name          = "ExecutionRole"
    static_value  = aws_iam_role.ssm_automation_role.arn
  }
}













resource "null_resource" "run_ssm_lambda_automation" {
  provisioner "local-exec" {
    command = <<EOT
      aws ssm start-automation-execution \
        --document-name InvokeLambdaFunction-Direct \
        --parameters InstanceId=i-087ad23f3a307f684,ExecutionRole=${aws_iam_role.ssm_automation_role.arn} \
        --region us-east-1 \
        --profile account-b
EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}
