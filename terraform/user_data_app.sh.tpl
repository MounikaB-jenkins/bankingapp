#!/usr/bin/env bash
set -euo pipefail

cat > /etc/bankingapp.env <<EOF
DB_SECRET_ARN=${db_secret_arn}
EOF
