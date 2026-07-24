#!/usr/bin/env bash
set -euo pipefail

# Install dependencies
sudo yum update -y
sudo yum install -y wget tar jq

cd /tmp

# Install Prometheus 3.6.0
wget https://github.com/prometheus/prometheus/releases/download/v3.6.0/prometheus-3.6.0.linux-amd64.tar.gz
tar -xzf prometheus-3.6.0.linux-amd64.tar.gz

# Create prometheus user
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus

# Create directories
sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus

# Install Prometheus binaries
sudo cp prometheus-3.6.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-3.6.0.linux-amd64/promtool /usr/local/bin/
sudo cp prometheus-3.6.0.linux-amd64/prometheus.yml /etc/prometheus/
sudo cp -r prometheus-3.6.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-3.6.0.linux-amd64/console_libraries /etc/prometheus/

# Set permissions
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown -R prometheus:prometheus /var/lib/prometheus

# Create Prometheus systemd service
sudo tee /etc/systemd/system/prometheus.service >/dev/null <<'EOF'
[Unit]
Description=Prometheus Monitoring Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple

ExecStart=/usr/local/bin/prometheus \
--config.file=/etc/prometheus/prometheus.yml \
--web.listen-address=0.0.0.0:9090 \
--storage.tsdb.path=/var/lib/prometheus \
--web.console.templates=/etc/prometheus/consoles \
--web.console.libraries=/etc/prometheus/console_libraries

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create Prometheus config
sudo tee /etc/prometheus/prometheus.yml >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093

rule_files:
  - /etc/prometheus/alert.rules

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
sudo mkdir -p /etc/prometheus
sudo tee /etc/prometheus/alert.rules >/dev/null <<'EOF'
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
wget https://dl.grafana.com/oss/release/grafana-10.4.5.linux-amd64.tar.gz
tar -xzf grafana-10.4.5.linux-amd64.tar.gz
sudo mv grafana-10.4.5 /opt/grafana

# Create Grafana user and directories
sudo useradd --no-create-home --shell /usr/sbin/nologin grafana
sudo mkdir -p /var/lib/grafana
sudo chown -R grafana:grafana /opt/grafana
sudo chown -R grafana:grafana /var/lib/grafana

# Create Grafana systemd service
sudo tee /etc/systemd/system/grafana.service >/dev/null <<'EOF'
[Unit]
Description=Grafana
After=network-online.target
Wants=network-online.target

[Service]
User=grafana
Group=grafana
Type=simple
WorkingDirectory=/opt/grafana
ExecStart=/opt/grafana/bin/grafana-server --homepath=/opt/grafana --config=/opt/grafana/conf/defaults.ini
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create Grafana datasource config for Prometheus
sudo mkdir -p /opt/grafana/provisioning/datasources
sudo tee /opt/grafana/provisioning/datasources/prometheus.yml >/dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# Install Alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.26.0.linux-amd64.tar.gz
sudo mv alertmanager-0.26.0.linux-amd64 /opt/alertmanager

# Create Alertmanager user
sudo useradd --no-create-home --shell /usr/sbin/nologin alertmanager
sudo mkdir -p /var/lib/alertmanager
sudo chown -R alertmanager:alertmanager /opt/alertmanager
sudo chown -R alertmanager:alertmanager /var/lib/alertmanager

# Create Alertmanager config
sudo mkdir -p /etc/alertmanager
sudo tee /etc/alertmanager/alertmanager.yml >/dev/null <<'EOF'
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

# Create Alertmanager systemd service
sudo tee /etc/systemd/system/alertmanager.service >/dev/null <<'EOF'
[Unit]
Description=Alertmanager
After=network-online.target
Wants=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/opt/alertmanager/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start all services
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl enable grafana
sudo systemctl enable alertmanager

sudo systemctl start prometheus
sudo systemctl start grafana
sudo systemctl start alertmanager

# Verify services are running
echo "=== Verifying Services ==="
sudo systemctl status prometheus --no-pager || true
sudo systemctl status grafana --no-pager || true
sudo systemctl status alertmanager --no-pager || true

echo ""
echo "=== Installation Complete ==="
echo "Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):9090"
echo "Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):3000 (admin/admin)"
echo "Alertmanager: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):9093"
