#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Terraform is required" >&2
  exit 1
fi

if ! command -v packer >/dev/null 2>&1; then
  echo "Packer is required" >&2
  exit 1
fi

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r app/requirements.txt pytest
pytest -q app/tests

cd packer
packer init flask-app.pkr.hcl
packer build -var "region=${AWS_REGION:-eu-central-1}" flask-app.pkr.hcl
packer init monitoring.pkr.hcl
packer build -var "region=${AWS_REGION:-eu-central-1}" monitoring.pkr.hcl

cd ../terraform
terraform init
terraform apply -auto-approve -var "region=${AWS_REGION:-ap-south-2}" -var-file=terraform.tfvars
