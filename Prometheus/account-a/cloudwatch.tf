resource "aws_instance" "cloudwatch_exporter" {
  ami           = "ami-0bdd88bd06d16ba03"
  instance_type = "t3.micro"
  key_name      = var.your-key-name
  subnet_id     = var.your-subnet-id
  vpc_security_group_ids = [aws_security_group.cloudwatch_export_sg.id]
  associate_public_ip_address = true


  iam_instance_profile = aws_iam_instance_profile.cloudwatch_exporter_profile.name # 需具备 CloudWatchReadOnlyAccess 权限

  user_data = file("cloudwatch-userdata.sh")

  tags = {
    Name = "cloudwatch-exporter-node"
  }
}



# 1. IAM Role
resource "aws_iam_role" "cloudwatch_exporter_role" {
  name = "cloudwatch-exporter-role"

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

# 2. 附加 CloudWatch 只读权限
resource "aws_iam_role_policy_attachment" "cloudwatch_exporter_attach" {
  role       = aws_iam_role.cloudwatch_exporter_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# 3. Instance Profile
resource "aws_iam_instance_profile" "cloudwatch_exporter_profile" {
  name = "cloudwatch-exporter-profile"
  role = aws_iam_role.cloudwatch_exporter_role.name
}



resource "aws_security_group" "cloudwatch_export_sg" {
  name        = "cloudwatch-exporter-sg"
  vpc_id      = var.vpc_id

  # 入向：允许 SSH
  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 建议改成你的办公网段
  }

  # 入向：允许 Prometheus 节点访问 Exporter 9106
  ingress {
    description = "Allow Prometheus scrape"
    from_port   = 9106
    to_port     = 9106
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.prometheus.private_ip}/32"] # 或者 Prometheus 所在子网段
  }

  # ICMP ping
  ingress {
    description = "Allow ping (ICMP) from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Prometheus scrape"
    from_port   = 9115
    to_port     = 9115
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.prometheus.private_ip}/32"] # 或者 Prometheus 所在子网段
  }

  # 出向：允许所有
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloudwatch-exporter-sg"
  }
}