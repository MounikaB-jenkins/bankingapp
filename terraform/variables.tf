variable "trusted_ip_cidr" {
  description = "A list of trusted IP CIDR blocks for SSH, monitoring, and DB init access."
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: This is insecure. Replace with your IP, e.g., ["your_ip/32"]
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = "" # e.g. "vpc-1234567890abcdef0"
}

variable "subnet_ids" {
  description = "Existing subnet IDs"
  type        = list(string)
  default     = [] # e.g. ["subnet-12345678", "subnet-abcdefgh"]
}

variable "create_vpc" {
  description = "When true, Terraform will create a new VPC and subnets instead of using existing ones"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the created VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "List of CIDR blocks for subnets to create when create_vpc=true"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
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
