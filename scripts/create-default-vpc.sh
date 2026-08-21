#!/usr/bin/env bash
set -euo pipefail

REGION=${1:-"eu-central-1"}
VPC_NAME=${2:-"packer-default-vpc"}

echo "Creating default VPC in region: $REGION"

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $REGION --query "Vpc.VpcId" --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION
echo "Created VPC: $VPC_ID"

# Enable DNS settings (required for RDS)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value": true}' --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value": true}' --region $REGION

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION
echo "Created and attached IGW: $IGW_ID"

# Get available AZs
AZS=$(aws ec2 describe-availability-zones --region $REGION --query "AvailabilityZones[].ZoneName" --output text)

# Create subnets in each AZ (minimum 2 for RDS/ALB requirements)
SUBNET_IDS=()
AZ_ARRAY=($AZS)
for i in "${!AZ_ARRAY[@]}"; do
  AZ="${AZ_ARRAY[$i]}"
  SUBNET_CIDR="10.0.$((i+1)).0/24"
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR --availability-zone $AZ --region $REGION --query "Subnet.SubnetId" --output text)
  SUBNET_IDS+=($SUBNET_ID)
  aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value="${VPC_NAME}-subnet-$((i+1))" --region $REGION
  echo "Created subnet $SUBNET_ID in AZ $AZ"
done

# Ensure at least 2 subnets for RDS/ALB requirements
if [ ${#SUBNET_IDS[@]} -lt 2 ]; then
  echo "ERROR: Need at least 2 subnets in different AZs for RDS and ALB. Only created ${#SUBNET_IDS[@]} subnet(s)."
  exit 1
fi

# Create route table with default route to IGW
RTB_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
echo "Created route table: $RTB_ID"

# Associate route table with all subnets
for SUBNET_ID in "${SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID --region $REGION
  aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch --region $REGION
done

# Export variables for parent shell to use
export VPC_ID
SUBNET_ID=${SUBNET_IDS[0]}
export SUBNET_ID

# Export all subnet IDs as comma-separated list for Terraform
SUBNET_IDS_LIST=$(IFS=,; echo "${SUBNET_IDS[*]}")
export SUBNET_IDS_LIST

# Output environment variables for Jenkins
echo ""
echo "=== VPC Configuration for Packer ==="
echo "VPC_ID=$VPC_ID"
echo "SUBNET_ID=$SUBNET_ID"
echo "SUBNET_IDS=$SUBNET_IDS_LIST"
echo "REGION=$REGION"
echo ""
echo "Use these in Jenkins:"
echo "export VPC_ID=$VPC_ID"
echo "export SUBNET_ID=$SUBNET_ID"
echo "export SUBNET_IDS=$SUBNET_IDS_LIST"
