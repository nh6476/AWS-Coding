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


#################################################跨账户S3存取，KMS加密################################################
#---A账户中创建KMS密码，B账户中创建S3桶
#---B账户的S3桶使用A账户的KMS进行加密
#---A账户将自己的cloudtrail保存在B账户的S3桶中




# 获取当前账户信息
# 获取 A 账户信息
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



# 创建 KMS CMK
resource "aws_kms_key" "cloudtrail_key" {
  provider                = aws.account_a
  description             = "Customer managed KMS key for CloudTrail logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 允许 A 账户的 CloudTrail 服务使用此 Key 来加密日志
      {
        Sid    = "AllowCloudTrailUseKey",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = [
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:Decrypt",       # 🔑 补充：CloudTrail 也会调用 Decrypt
          "kms:DescribeKey"
        ],
        Resource = "*",
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.a.account_id
            # 可选更严格： "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.a.account_id}:trail/account-a-cloudtrail"
          }
        }
      },

      # 允许 A 账户管理员完全管理此 Key
      {
        Sid    = "AllowAccountAdmins",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.a.account_id}:root"
        },
        Action = "kms:*",
        Resource = "*"
      },

      # 允许 B 账户中的读取者主体（用户/角色）解密日志
      {
        Sid    = "AllowBReadersDecrypt",
        Effect = "Allow",
        Principal = {
          AWS = var.b_reader_principals  # e.g., ["arn:aws:iam::<B>:role/S3LogReader"]
        },
        Action = [
          "kms:Decrypt",       # 🔑 必需：解密日志对象
          "kms:DescribeKey",   # 🔑 必需：查看 Key 元数据
          "kms:ListAliases",   # 🔧 可选：避免控制台/SDK 报错
          "kms:ListKeys"       # 🔧 可选：避免控制台/SDK 报错
        ],
        Resource = "*"
      }
    ]
  })
}

# 可选：为 Key 创建别名，方便引用
resource "aws_kms_alias" "cloudtrail_key_alias" {
  provider      = aws.account_a
  name          = "alias/cloudtrail-logs-key"
  target_key_id = aws_kms_key.cloudtrail_key.key_id
}








# 在 A 账户创建 CMK，供 B 账户的 S3 桶做 SSE-KMS
resource "aws_kms_key" "for_b_bucket_sse" {
  provider                = aws.account_a
  description             = "CMK in Account A for SSE-KMS on bucket in Account B"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 允许 A 账户管理员完全管理此 Key
      {
        Sid    = "AllowAccountAAdminsManageKey",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.a.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },

      # 允许 S3 服务在 B 账户的指定桶上使用此 Key 进行 SSE-KMS
      {
        Sid    = "AllowS3ServiceUseForBucketInB",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = [
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:Decrypt",      # 🔑 保留，S3 在某些场景会调用
          "kms:DescribeKey"
        ],
        Resource = "*",
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.b.account_id
          },
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:s3:::${var.b_bucket_name}"
          }
        }
      },

      # 允许 B 账户中的读取者主体（用户/角色）解密对象
      {
        Sid    = "AllowBReadersDecrypt",
        Effect = "Allow",
        Principal = {
          AWS = var.b_reader_principals  # e.g., ["arn:aws:iam::<B>:role/S3LogReader"]
        },
        Action = [
          "kms:Decrypt",       # 🔑 必需：解密对象
          "kms:DescribeKey",   # 🔑 必需：查看 Key 元数据
          "kms:ListAliases",   # 🔧 建议：避免控制台/SDK 报错
          "kms:ListKeys"       # 🔧 建议：避免控制台/SDK 报错
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_kms_alias" "for_b_bucket_sse_alias" {
  provider      = aws.account_a
  name          = "alias/bucket-b-sse"
  target_key_id = aws_kms_key.for_b_bucket_sse.key_id
}







#################################################B账号下常见桶################################################

resource "aws_s3_bucket" "cloudtrail_logs_bucket" {
  provider = aws.account_b
  bucket   = var.b_bucket_name
}

# 配置桶的默认加密，引用 A 账户的 CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_sse" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.cloudtrail_logs_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_alias.for_b_bucket_sse_alias.id   # A账户CMK的完整ARN
    }
    bucket_key_enabled = true  # 降低KMS调用成本（仅SSE-KMS支持）
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  provider = aws.account_b
  bucket = aws_s3_bucket.cloudtrail_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 允许 CloudTrail 服务写入日志对象
      {
        Sid: "AWSCloudTrailWrite",
        Effect: "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:PutObject",
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs_bucket.id}/AWSLogs/${data.aws_caller_identity.a.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      # 允许 CloudTrail 检查桶 ACL 和策略
      {
        Sid: "AWSCloudTrailAclCheck",
        Effect: "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:GetBucketAcl",
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs_bucket.id}"
      }
    ]
  })
}


#################################################A账号下的cloudtrail################################################

resource "aws_cloudtrail" "account_a_existing_trail" {
  depends_on  = [aws_s3_bucket_policy.cloudtrail_bucket_policy]  
  provider                      = aws.account_a
  name                          = "default"
  s3_bucket_name                = var.b_bucket_name
  kms_key_id                    = aws_kms_key.cloudtrail_key.arn
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}

