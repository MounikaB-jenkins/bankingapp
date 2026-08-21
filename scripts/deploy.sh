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
export PYTHONPATH=$PYTHONPATH:$(pwd)
pytest -q app/tests

# Determine VPC/Subnet IDs based on configuration
VPC_ID=""
SUBNET_ID=""

if [ "${CREATE_VPC:-true}" = "true" ]; then
  # Create VPC and subnets first to get IDs
  cd terraform
  terraform init
  terraform apply -auto-approve -var "region=${AWS_REGION:-eu-west-1}" -var="create_vpc=true" -var-file=terraform.tfvars
  
  # Extract VPC and Subnet IDs from Terraform outputs
  VPC_ID=$(terraform output -raw effective_vpc_id)
  SUBNET_IDS=$(terraform output -raw effective_subnet_ids | tr -d '[]"' | tr ',' ' ')
  SUBNET_ID=$(echo $SUBNET_IDS | awk '{print $1}')
  
  cd ../packer
else
  # Use existing VPC and subnet from environment variables
  VPC_ID="${VPC_ID:-}"
  SUBNET_ID="${SUBNET_ID:-}"
  
  if [ -z "$VPC_ID" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: VPC_ID and SUBNET_ID environment variables are required when CREATE_VPC=false"
    exit 1
  fi
fi

# Build AMIs with VPC configuration
packer init flask-app.pkr.hcl
packer build -var "region=${AWS_REGION:-eu-west-1}" -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}" flask-app.pkr.hcl

packer init monitoring.pkr.hcl
packer build -var "region=${AWS_REGION:-eu-west-1}" -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}" monitoring.pkr.hcl

# Deploy infrastructure (only if using existing VPC)
if [ "${CREATE_VPC:-false}" = "false" ]; then
  cd ../terraform
  terraform init
  terraform apply -auto-approve -var "region=${AWS_REGION:-eu-west-1}" -var-file=terraform.tfvars
fi
