#!/usr/bin/env bash
# Script to get VPC and Subnet IDs for eu-central-1
# Run this: ./scripts/get-aws-resources.sh

echo "========================================="
echo "AWS Resources in eu-central-1 for BankingApp"
echo "========================================="
echo ""

echo "--- VPCs in eu-central-1 ---"
aws ec2 describe-vpcs --region eu-central-1 --query 'Vpcs[*].[VpcId, CidrBlock, Tags[?Key==`Name`].Value | [0]]' --output table
echo ""

echo "--- Subnets in eu-central-1 ---"
aws ec2 describe-subnets --region eu-central-1 --query 'Subnets[*].[SubnetId, VpcId, AvailabilityZone, CidrBlock, Tags[?Key==`Name`].Value | [0]]' --output table
echo ""

echo "--- Security Groups in eu-central-1 ---"
aws ec2 describe-security-groups --region eu-central-1 --query 'SecurityGroups[*].[GroupId, GroupName, VpcId, Description]' --output table
echo ""

echo "========================================="
echo "To update terraform/terraform.tfvars:"
echo "========================================="
echo ""
echo "1. Copy the VPC ID from the table above"
echo "2. Copy the Subnet IDs (at least 2) from the table above"
echo "3. Edit terraform/terraform.tfvars and replace the placeholders"
echo ""
echo "Example terraform.tfvars:"
echo "  vpc_id = \"vpc-0123456789abcdef0\""
echo "  subnet_ids = [\"subnet-0123456789abcdef0\", \"subnet-abcdef01234567890\"]"
