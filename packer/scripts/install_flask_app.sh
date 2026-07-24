#!/usr/bin/env bash
set -euo pipefail

# Use yum for Amazon Linux 2
sudo yum update -y || true

# Install nginx from Amazon Linux Extras
sudo amazon-linux-extras install nginx1 -y || true

# Install PostgreSQL client
sudo yum install -y postgresql || true

# Install Python and dependencies
sudo yum install -y python3 python3-pip git awscli || true
sudo python3 -m pip install --upgrade pip || true

# Install Flask with Python 3.7 compatible version
sudo python3 -m pip install "Flask==2.3.3" || true
sudo python3 -m pip install prometheus-client==0.20.0 boto3==1.35.4 psycopg2-binary==2.9.2 || true

# Install Node Exporter for metrics scraping
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz -O node_exporter.tar.gz || { echo "Node Exporter download failed"; exit 1; }
sudo tar -xzf node_exporter.tar.gz -C /usr/local || { echo "Node Exporter extract failed"; exit 1; }
sudo mv /usr/local/node_exporter-*/node_exporter /usr/local/bin/node_exporter || { echo "Node Exporter move failed"; exit 1; }
sudo chmod +x /usr/local/bin/node_exporter || { echo "Node Exporter chmod failed"; exit 1; }

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

# Create app directory
sudo mkdir -p /opt/bankingapp
sudo cp -r /tmp/bankingapp-app /opt/bankingapp/app

# Create Flask app systemd service
sudo tee /etc/systemd/system/bankingapp.service >/dev/null <<'EOF'
[Unit]
Description=BankingApp Flask service
After=network.target

[Service]
WorkingDirectory=/opt/bankingapp/app
Environment=ENVIRONMENT=prod
ExecStart=/usr/bin/python3 /opt/bankingapp/app/app.py
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

# Enable and START all services
sudo systemctl daemon-reload
sudo systemctl enable bankingapp.service
sudo systemctl enable nginx1
sudo systemctl enable node_exporter

sudo systemctl start bankingapp.service
sudo systemctl start nginx1
sudo systemctl start node_exporter

echo "=== Flask App Services Started ==="
