#!/usr/bin/env bash
set -euo pipefail

# Use yum for Amazon Linux 2 (more reliable than dnf)
sudo yum update -y || true
sudo yum install -y wget tar jq || true
sudo mkdir -p /opt/prometheus /opt/grafana /opt/alertmanager

cd /tmp

# Install Prometheus
sudo wget -q https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz -O prometheus.tar.gz || true
sudo tar -xzf prometheus.tar.gz || true
sudo cp -r prometheus-2.54.1.linux-amd64/* /opt/prometheus/ || true

# Install Alertmanager
sudo wget -q https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz -O alertmanager.tar.gz || true
sudo tar -xzf alertmanager.tar.gz || true
sudo cp -r alertmanager-0.26.0.linux-amd64/* /opt/alertmanager/ || true
sudo mv /opt/alertmanager/alertmanager /usr/local/bin/alertmanager || true
sudo mv /opt/alertmanager/amtool /usr/local/bin/amtool || true

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

# Create Prometheus config with Node Exporter scraping and Alertmanager
sudo tee /opt/prometheus/prometheus.yml >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alertmanager configuration
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093

# Rule files for alerts
rule_files:
  - /opt/prometheus/alert.rules

# Scrape configs
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

  - alert: HighMemory
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage on {{ $labels.instance }}"
      description: "Memory usage on {{ $labels.instance }} is {{ $value }}% for 5 minutes."
EOF

# Install Grafana
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

sudo tee /etc/systemd/system/alertmanager.service >/dev/null <<'EOF'
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

# Enable all services
sudo systemctl daemon-reload
sudo systemctl enable prometheus.service
sudo systemctl enable alertmanager.service
sudo systemctl enable grafana.service
