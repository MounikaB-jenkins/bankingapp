# AWS Region
region = "eu-central-1"

# VPC Configuration
vpc_id = "vpc-02b2d5872e4eaa025"

# Subnet IDs
subnet_ids = ["subnet-03f9f842b9a125975", "subnet-02c1f0c7939d0978c"]

# AMI IDs (will be auto-populated by Jenkins pipeline after Packer build)
flask_ami_id = ""
monitoring_ami_id = ""

# EC2 Instance Types
instance_type = "t3.micro"
monitoring_instance_type = "t3.micro"

# Database Configuration
db_name = "bankingapp"
db_username = "bankingapp_admin"
