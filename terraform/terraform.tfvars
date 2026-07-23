# AWS Region
region = "ap-south-1"

# VPC Configuration
vpc_id = "REPLACE_WITH_YOUR_VPC_ID"

# Subnet IDs (comma-separated list)
subnet_ids = ["REPLACE_WITH_YOUR_SUBNET_ID_1", "REPLACE_WITH_YOUR_SUBNET_ID_2"]

# AMI IDs (will be populated by Jenkins pipeline after Packer build)
flask_ami_id = ""
monitoring_ami_id = ""

# EC2 Instance Types
instance_type = "t3.micro"
monitoring_instance_type = "t3.micro"

# Database Configuration
db_name = "bankingapp"
db_username = "bankingapp_admin"
