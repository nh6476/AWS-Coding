resource "aws_instance" "prometheus" {
  ami           = "ami-0bdd88bd06d16ba03" # Amazon Linux 2 AMI（请根据区域更新）
  instance_type = "t3.small"
  key_name      = var.your-key-name
  subnet_id     = var.your-subnet-id
#   security_groups = [aws_security_group.prometheus_sg.name]
  vpc_security_group_ids = [aws_security_group.prometheus_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  iam_instance_profile = aws_iam_instance_profile.prometheus_profile.name
  user_data = file("prometheus-userdata.sh")

  tags = {
    Name = "prometheus-node"
  }
}



# 1. IAM Role
resource "aws_iam_role" "prometheus_role" {
  name = "prometheus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# 2. 附加 CloudWatch 只读权限（Prometheus 可能需要抓取 CloudWatch 指标）
resource "aws_iam_role_policy_attachment" "prometheus_attach" {
  role       = aws_iam_role.prometheus_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# 3. Instance Profile
resource "aws_iam_instance_profile" "prometheus_profile" {
  name = "prometheus-profile"
  role = aws_iam_role.prometheus_role.name
}





resource "aws_security_group" "prometheus_sg" {
  name        = "prometheus-sg"
  description = "Allow SSH, ping, and Prometheus Web UI; allow all outbound"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP ping
  ingress {
    description = "Allow ping (ICMP) from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus Web UI
  ingress {
    description = "Allow Prometheus Web UI (9090)"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 建议改成你的办公 IP 或跳板机段
  }

  # 出向全部放行
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prometheus-sg"
  }
}

