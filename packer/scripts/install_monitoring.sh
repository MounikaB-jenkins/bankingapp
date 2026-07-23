#!/usr/bin/env bash
set -euo pipefail

# Use yum for Amazon Linux 2 (more reliable than dnf)
sudo yum update -y || true
sudo yum install -y wget tar jq || true
sudo mkdir -p /opt/prometheus /opt/grafana

cd /tmp
sudo wget -q https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz -O prometheus.tar.gz || true
sudo tar -xzf prometheus.tar.gz || true
sudo cp -r prometheus-2.54.1.linux-amd64/* /opt/prometheus/ || true

# Create prometheus config
sudo tee /opt/prometheus/prometheus.yml >/dev/null <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'bankingapp'
    static_configs:
      - targets: ['localhost:9100']
EOF

sudo wget -q https://dl.grafana.com/oss/release/grafana-10.4.5.linux-amd64.tar.gz -O grafana.tar.gz || true
sudo tar -xzf grafana.tar.gz || true
sudo cp -r grafana-10.4.5 /opt/grafana || true

# Create systemd services
sudo tee /etc/systemd/system/prometheus.service >/dev/null <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/grafana.service >/dev/null <<'EOF'
[Unit]
Description=Grafana
After=network.target

[Service]
ExecStart=/opt/grafana/grafana-10.4.5/bin/grafana-server --homepath=/opt/grafana/grafana-10.4.5
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus.service grafana.service
