#!/bin/bash
yum update -y
yum install -y wget curl tar

# 安装 Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.47.0/prometheus-2.47.0.linux-amd64.tar.gz
tar -xzf prometheus-2.47.0.linux-amd64.tar.gz
mv prometheus-2.47.0.linux-amd64 prometheus
ln -s /opt/prometheus/prometheus /usr/local/bin/prometheus

# 创建配置文件
mkdir -p /etc/prometheus
cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 5m

scrape_configs:
  - job_name: 'cloudwatch'
    static_configs:
      - targets: ['<cloudwatch-exporter-private-ip>:9106']
EOF

# 启动 Prometheus
nohup prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.listen-address=:9090 &
