variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = "vpc-088237085ff583c8e"
}

variable "subnet_ids" {
  description = "Existing subnet IDs"
  type        = list(string)
  default     = ["subnet-0e2b2454962fb5acf"]
}

variable "flask_ami_id" {
  description = "AMI ID built by Packer for the Flask app"
  type        = string
  default     = ""
}

variable "monitoring_ami_id" {
  description = "AMI ID built by Packer for the monitoring server"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for app instances"
  type        = string
  default     = "t3.micro"
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for the monitoring server"
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = "Database name for the BankingApp PostgreSQL instance"
  type        = string
  default     = "bankingapp"
}

variable "db_username" {
  description = "Master username for the PostgreSQL instance"
  type        = string
  default     = "bankingapp_admin"
}
