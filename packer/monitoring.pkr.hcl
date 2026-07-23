variable "region" {
  type    = string
  default = "eu-central-1"
}

source "amazon-ebs" "monitoring" {
  ami_name      = "bankingapp-monitoring-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region
  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"]
  }
  ssh_username = "ec2-user"
  tags = {
    Name    = "bankingapp-monitoring"
    Project = "BankingApp"
  }
  
  # Security group for the temporary instance
  security_group_filter {
    source_group_name = "default"
  }
}

build {
  sources = ["source.amazon-ebs.monitoring"]

  provisioner "shell" {
    script = "./scripts/install_monitoring.sh"
  }
}
