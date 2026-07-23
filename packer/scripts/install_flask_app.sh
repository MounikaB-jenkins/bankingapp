#!/usr/bin/env bash
set -euo pipefail

sudo dnf update -y
sudo dnf install -y python3 python3-pip git nginx postgresql15 awscli
sudo python3 -m pip install --upgrade pip
sudo mkdir -p /opt/bankingapp
sudo cp -r /tmp/bankingapp-app /opt/bankingapp/app
sudo python3 -m pip install -r /opt/bankingapp/app/requirements.txt

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
