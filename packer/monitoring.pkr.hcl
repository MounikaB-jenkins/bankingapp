variable "region" {
  type    = string
  default = "ap-south-2"
}

source "amazon-ebs" "monitoring" {
  ami_name      = "bankingapp-monitoring-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
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
}

build {
  sources = ["source.amazon-ebs.monitoring"]

  provisioner "shell" {
    script = "./scripts/install_monitoring.sh"
  }
}
