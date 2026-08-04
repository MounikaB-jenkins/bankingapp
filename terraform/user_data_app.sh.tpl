#!/usr/bin/env bash
set -euo pipefail

cat > /etc/bankingapp.env <<EOF
DB_SECRET_ARN=${db_secret_arn}
AWS_REGION=${aws_region}
FLASK_SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32)
EOF

# Start the bankingapp service after environment variables are set
systemctl start bankingapp.service
