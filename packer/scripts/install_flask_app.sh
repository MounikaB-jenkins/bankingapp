#!/usr/bin/env bash
set -euo pipefail

# Aggressively stop and disable automatic updates to prevent yum lock conflicts.
# The service might not exist, so we use '|| true' to prevent script failure.
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

echo "--- Installing nginx with retry ---"
for i in {1..5}; do
    timeout 300 sudo amazon-linux-extras install nginx1 -y && break
    echo "Attempt $i: Nginx install failed, likely due to a lock. Killing processes and retrying in 10s..."
    sudo pkill -9 -f yum || true; sudo rm -f /var/run/yum.pid; sleep 10
done

echo "--- Installing other packages with retry ---"
for i in {1..5}; do
    # Install postgresql14 client and other dependencies.
    # amazon-linux-extras is the standard way to install specific package versions on Amazon Linux 2.
    timeout 300 sudo amazon-linux-extras install postgresql14 -y && sudo yum install -y python3-pip git awscli jq && break
    echo "Attempt $i: Yum install failed, likely due to a lock. Killing processes and retrying in 10s..."
    sudo pkill -9 -f yum || true; sudo rm -f /var/run/yum.pid; sleep 10
done

echo "--- Upgrading pip ---"
sudo python3 -m pip install --upgrade pip

# Create a non-privileged user for the application
echo "--- Creating bankingapp user ---"
id -u bankingapp &>/dev/null || sudo useradd --no-create-home --shell /bin/false bankingapp

# Create app directory and set up a virtual environment
sudo mkdir -p /opt/bankingapp
sudo chown -R bankingapp:bankingapp /opt/bankingapp
sudo -u bankingapp python3 -m venv /opt/bankingapp/venv

# Install Python dependencies into the virtual environment
# Run pip install as the 'bankingapp' user to ensure correct file permissions inside the venv
sudo -u bankingapp /opt/bankingapp/venv/bin/pip install -r /tmp/bankingapp-app/requirements.txt

# Deploy the application code to a 'src' directory to avoid module name conflicts.
sudo mkdir -p /opt/bankingapp/src
sudo cp -r /tmp/bankingapp-app/* /opt/bankingapp/src/
sudo chown -R bankingapp:bankingapp /opt/bankingapp/src

# --- Node Exporter Installation ---
# Install Node Exporter for metrics scraping. Runs as ec2-user.
cd /tmp
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

# Create a dedicated user for node_exporter
echo "--- Creating node_exporter user ---"
id -u node_exporter &>/dev/null || sudo useradd --no-create-home --shell /bin/false node_exporter

# Create Node Exporter systemd service
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always
User=node_exporter

[Install]
WantedBy=multi-user.target
EOF

if [ ! -f /etc/systemd/system/node_exporter.service ]; then
    echo "ERROR: Node Exporter service file was not created at /etc/systemd/system/node_exporter.service" >&2
    exit 1
fi

# Create Nginx reverse proxy configuration
sudo tee /etc/nginx/conf.d/bankingapp.conf >/dev/null <<'EOF'
server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
# Remove default Nginx config to avoid port 80 conflicts
sudo rm -f /etc/nginx/conf.d/default.conf

# Create Flask app systemd service
sudo tee /etc/systemd/system/bankingapp.service >/dev/null <<'EOF'
[Unit]
Description=BankingApp Flask Service
After=network.target

[Service]
WorkingDirectory=/opt/bankingapp/src
EnvironmentFile=/etc/bankingapp.env
ExecStart=/opt/bankingapp/venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8000 app:app
Restart=always
User=bankingapp
Group=bankingapp

[Install]
WantedBy=multi-user.target
EOF

if [ ! -f /etc/systemd/system/bankingapp.service ]; then
    echo "ERROR: BankingApp service file was not created at /etc/systemd/system/bankingapp.service" >&2
    exit 1
fi

# Enable and START all services
sudo systemctl daemon-reload
sudo systemctl enable bankingapp.service

# Verify nginx installed correctly before trying to enable it
if ! sudo systemctl list-unit-files | grep -q '^nginx.service'; then
    echo "ERROR: nginx.service not found. The 'amazon-linux-extras install nginx1' command may have failed." >&2
    exit 1
fi
sudo systemctl enable nginx
sudo systemctl enable node_exporter

# Do NOT start bankingapp.service here. It depends on the DB_SECRET_ARN environment
# variable which is only supplied via user_data at instance launch time.
# The service will be started automatically on boot.
sudo systemctl start nginx
sudo systemctl start node_exporter

echo "=== Flask App Services Enabled ==="
