# AWS Region
region = "eu-central-1"

# VPC Configuration - REPLACE THESE VALUES WITH YOUR ACTUAL AWS RESOURCES IN eu-central-1
# Run: aws ec2 describe-vpcs --region eu-central-1
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"  # REPLACE: Your VPC ID from AWS Console

# Subnet IDs - REPLACE THESE WITH YOUR ACTUAL SUBNET IDs FROM eu-central-1
# Run: aws ec2 describe-subnets --region eu-central-1
subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]

# AMI IDs (will be auto-populated by Jenkins pipeline after Packer build)
flask_ami_id = ""
monitoring_ami_id = ""

# EC2 Instance Types
instance_type = "t3.micro"
monitoring_instance_type = "t3.micro"

# Database Configuration
db_name = "bankingapp"
db_username = "bankingapp_admin"
