#!/bin/bash
yum update -y
yum install -y java-1.8.0-openjdk wget curl

# 下载 CloudWatch Exporter
mkdir -p /opt/cloudwatch_exporter
cd /opt/cloudwatch_exporter
wget https://github.com/prometheus/cloudwatch_exporter/releases/latest/download/cloudwatch_exporter.jar

# 创建配置文件
cat <<EOF > config.yml
region: ap-northeast-1
metrics:
  - aws_namespace: AWS/EC2
    aws_metric_name: CPUUtilization
    aws_dimensions: [InstanceId]
    aws_statistics: [Average]
    period_seconds: 300
    range_seconds: 600
EOF

# 启动 Exporter
nohup java -jar cloudwatch_exporter.jar 9106 config.yml &
