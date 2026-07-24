#!/usr/bin/env bash
set -euo pipefail

# Install dependencies
sudo yum update -y || true
sudo yum install -y wget tar jq || true
sudo mkdir -p /opt/prometheus /opt/grafana /opt/alertmanager

cd /tmp

# Install Prometheus
sudo wget -q https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz -O prometheus.tar.gz || { echo "Prometheus download failed"; exit 1; }
sudo tar -xzf prometheus.tar.gz || { echo "Prometheus extract failed"; exit 1; }
sudo cp -r prometheus-*/ /opt/prometheus/ || { echo "Prometheus copy failed"; exit 1; }

# Install Alertmanager
sudo wget -q https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz -O alertmanager.tar.gz || { echo "Alertmanager download failed"; exit 1; }
sudo tar -xzf alertmanager.tar.gz || { echo "Alertmanager extract failed"; exit 1; }
sudo cp -r alertmanager-*/ /opt/alertmanager/ || { echo "Alertmanager copy failed"; exit 1; }
sudo ln -sf /opt/alertmanager/alertmanager /usr/local/bin/alertmanager
sudo ln -sf /opt/alertmanager/amtool /usr/local/bin/amtool

# Create Alertmanager config
sudo mkdir -p /opt/alertmanager
sudo tee /opt/alertmanager/alertmanager.yml >/dev/null <<'EOF'
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: 'default-receiver'

receivers:
- name: 'default-receiver'
  email_configs:
  - to: 'operations-team@example.com'
    from: 'alertmanager@bankingapp.com'
    smarthost: 'smtp.example.com:587'
    auth_username: 'alertmanager@example.com'
    auth_password: 'your-password'
    require_tls: true
    send_resolved: true
EOF

# Create Prometheus config
sudo tee /opt/prometheus/prometheus.yml >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093

rule_files:
  - /opt/prometheus/alert.rules

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          env: 'monitoring'
EOF

# Create alert rules
sudo tee /opt/prometheus/alert.rules >/dev/null <<'EOF'
groups:
- name: instance_health
  rules:
  - alert: InstanceDown
    expr: up{job="node-exporter"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes."

  - alert: HighCPU
    expr: (100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)) > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage on {{ $labels.instance }}"
      description: "CPU usage on {{ $labels.instance }} is {{ $value }}% for 5 minutes."
EOF

# Install Grafana
sudo wget -q https://dl.grafana.com/oss/release/grafana-10.4.5.linux-amd64.tar.gz -O grafana.tar.gz || { echo "Grafana download failed"; exit 1; }
sudo tar -xzf grafana.tar.gz || { echo "Grafana extract failed"; exit 1; }
sudo mv grafana-*/ /opt/grafana || { echo "Grafana move failed"; exit 1; }

# Find actual Grafana binary path
GRAFANA_HOME=$(ls -d /opt/grafana/grafana-* 2>/dev/null | head -1)
if [ -z "$GRAFANA_HOME" ]; then
  echo "ERROR: Grafana directory not found in /opt/grafana"
  exit 1
fi

GRAFANA_BIN="$GRAFANA_HOME/bin/grafana-server"
if [ ! -f "$GRAFANA_BIN" ]; then
  echo "ERROR: Grafana binary not found at $GRAFANA_BIN"
  exit 1
fi

# Create Prometheus service
sudo tee /etc/systemd/system/prometheus.service >/dev/null <<EOF
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

# Create Alertmanager service
sudo tee /etc/systemd/system/alertmanager.service >/dev/null <<EOF
[Unit]
Description=Alertmanager
After=network.target

[Service]
ExecStart=/usr/local/bin/alertmanager --config.file=/opt/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Create Grafana service with correct path
sudo tee /etc/systemd/system/grafana.service >/dev/null <<EOF
[Unit]
Description=Grafana
After=network.target

[Service]
ExecStart=$GRAFANA_BIN --homepath=$GRAFANA_HOME
Restart=always
User=ec2-user
Environment=GF_PATHS_PROVISIONING=/opt/grafana/provisioning
Environment=GF_PATHS_CONF=/opt/grafana/conf

[Install]
WantedBy=multi-user.target
EOF

# Create directories for Grafana
sudo mkdir -p /opt/grafana/{provisioning/dashboards,provisioning/datasources,conf}

# Create Grafana datasource config for Prometheus
sudo tee /opt/grafana/provisioning/datasources/prometheus.yml >/dev/null <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# Reload systemd and enable services
sudo systemctl daemon-reload

# ENABLE AND START ALL SERVICES
sudo systemctl enable prometheus.service
sudo systemctl enable alertmanager.service
sudo systemctl enable grafana.service

sudo systemctl start prometheus.service
sudo systemctl start alertmanager.service
sudo systemctl start grafana.service

# Verify services are running
sudo systemctl status prometheus.service || true
sudo systemctl status alertmanager.service || true
sudo systemctl status grafana.service || true

echo "=== Services started ==="
echo "Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "IP-not-available"):9090"
echo "Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "IP-not-available"):3000"
echo "Alertmanager: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "IP-not-available"):9093"
