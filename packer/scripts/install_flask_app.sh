#!/usr/bin/env bash
set -euo pipefail

# Use yum for Amazon Linux 2 (more reliable than dnf)
sudo yum update -y || true
sudo yum install -y python3 python3-pip git nginx postgresql15 awscli || true
sudo python3 -m pip install --upgrade pip || true
sudo mkdir -p /opt/bankingapp
sudo cp -r /tmp/bankingapp-app /opt/bankingapp/app
sudo python3 -m pip install -r /opt/bankingapp/app/requirements.txt || true

# Create systemd service
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

sudo systemctl daemon-reload
sudo systemctl enable bankingapp.service
sudo systemctl enable nginx
