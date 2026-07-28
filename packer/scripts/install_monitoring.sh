#!/usr/bin/env bash
set -euo pipefail

# Aggressively stop and disable automatic updates to prevent yum lock conflicts.
sudo systemctl stop yum-cron || true
sudo systemctl disable yum-cron || true

# Kill any lingering yum process and remove the lock file to take control.
echo "Forcefully stopping any existing yum processes..."
sudo pkill -9 -f yum || true
sudo rm -f /var/run/yum.pid

echo "--- Running yum update with retry ---"
for i in {1..5}; do
    timeout 300 sudo yum update -y && break
    echo "Attempt $i: Yum update failed, likely due to a lock. Killing processes and retrying in 10s..."
    sudo pkill -9 -f yum || true; sudo rm -f /var/run/yum.pid; sleep 10
done

echo "--- Installing dependencies with retry ---"
for i in {1..5}; do
    timeout 300 sudo yum install -y wget tar jq && break
    echo "Attempt $i: Yum install failed, likely due to a lock. Killing processes and retrying in 10s..."
    sudo pkill -9 -f yum || true; sudo rm -f /var/run/yum.pid; sleep 10
done

cd /tmp

# Install Prometheus v3.13.1
PROM_VERSION="3.13.1"
PROM_ARCHIVE="prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
echo "--- Downloading Prometheus ${PROM_VERSION} with retry ---"
for i in {1..5}; do
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_ARCHIVE}" -O "${PROM_ARCHIVE}" && break
    echo "Attempt $i: Prometheus download failed. Retrying in 10s..."
    sleep 10
done

if [ ! -f "${PROM_ARCHIVE}" ]; then
    echo "ERROR: Prometheus download failed after multiple attempts." >&2
    exit 1
fi
tar -xvf "${PROM_ARCHIVE}"

# Create prometheus user
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus

# Install Prometheus binaries
sudo cp prometheus-${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/

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
--storage.tsdb.path=/var/lib/prometheus
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

  - job_name: "flask-app"
    metrics_path: /metrics
    # This will be dynamically discovered via a file_sd_config in a production setup
    static_configs:
      - targets: ['<APP_INSTANCE_IP>:8080'] # Placeholder, will need dynamic discovery
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

# Install Grafana via repository for easier updates
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

echo "--- Installing Grafana with retry ---"
for i in {1..5}; do
    timeout 300 sudo yum install -y grafana && break
    echo "Attempt $i: Grafana install failed, likely due to a lock. Killing processes and retrying in 10s..."
    sudo pkill -9 -f yum || true; sudo rm -f /var/run/yum.pid; sleep 10
done

# Create Grafana datasource config for Prometheus
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml >/dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# Install Alertmanager
AM_VERSION="0.26.0"
AM_ARCHIVE="alertmanager-${AM_VERSION}.linux-amd64.tar.gz"
echo "--- Downloading Alertmanager ${AM_VERSION} with retry ---"
for i in {1..5}; do
    wget -q "https://github.com/prometheus/alertmanager/releases/download/v${AM_VERSION}/${AM_ARCHIVE}" -O "${AM_ARCHIVE}" && break
    echo "Attempt $i: Alertmanager download failed. Retrying in 10s..."
    sleep 10
done

if [ ! -f "${AM_ARCHIVE}" ]; then
    echo "ERROR: Alertmanager download failed after multiple attempts." >&2
    exit 1
fi
tar -xzf "${AM_ARCHIVE}"
sudo mv "alertmanager-${AM_VERSION}.linux-amd64" /opt/alertmanager

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

# Install Node Exporter for self-monitoring
NE_VERSION="1.6.1"
NE_ARCHIVE="node_exporter-${NE_VERSION}.linux-amd64.tar.gz"
echo "--- Downloading Node Exporter ${NE_VERSION} with retry ---"
for i in {1..5}; do
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/${NE_ARCHIVE}" -O "${NE_ARCHIVE}" && break
    echo "Attempt $i: Node Exporter download failed. Retrying in 10s..."
    sleep 10
done

if [ ! -f "${NE_ARCHIVE}" ]; then
    echo "ERROR: Node Exporter download failed after multiple attempts." >&2
    exit 1
fi
sudo tar -xzf "${NE_ARCHIVE}" -C /usr/local
sudo mv "/usr/local/node_exporter-${NE_VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
sudo chmod +x /usr/local/bin/node_exporter

# Create Node Exporter systemd service
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start all services
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl enable grafana-server
sudo systemctl enable alertmanager
sudo systemctl enable node_exporter

sudo systemctl start prometheus
sudo systemctl start grafana-server
sudo systemctl start alertmanager
sudo systemctl start node_exporter

# Verify services are running
echo "=== Verifying Services ==="
sudo systemctl status prometheus --no-pager || true
sudo systemctl status grafana-server --no-pager || true
sudo systemctl status alertmanager --no-pager || true
sudo systemctl status node_exporter --no-pager || true

echo ""
echo "=== Installation Complete ==="
echo "Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):9090"
echo "Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):3000 (admin/admin)"
echo "Alertmanager: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost"):9093"
