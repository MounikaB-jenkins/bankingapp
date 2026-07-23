#!/usr/bin/env bash
set -euo pipefail

cat > /etc/bankingapp.env <<EOF
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USERNAME=${db_username}
DB_SECRET_ARN=${db_secret_arn}
EOF

systemctl restart bankingapp.service
