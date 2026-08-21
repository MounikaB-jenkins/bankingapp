variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

source "amazon-ebs" "flask" {
  ami_name      = "bankingapp-flask-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id
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
    Name    = "bankingapp-flask"
    Project = "BankingApp"
  }
}

build {
  sources = ["source.amazon-ebs.flask"]

  provisioner "file" {
    source      = "../app"
    destination = "/tmp/bankingapp-app"
  }

  provisioner "shell" {
    script = "./scripts/install_flask_app.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }
}
