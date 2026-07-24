terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#%^*-_"  # Removed @ which is not allowed by RDS
}

resource "aws_security_group" "app" {
  name        = "bankingapp-app-sg"
  description = "Allow app traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Node Exporter scraping from monitoring instance
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for monitoring instance
resource "aws_security_group" "monitoring" {
  name        = "bankingapp-monitoring-sg"
  description = "Allow access to monitoring services"
  vpc_id      = var.vpc_id

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Alertmanager
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "bankingapp-db-sg"
  description = "Allow PostgreSQL access from the app tier"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "bankingapp-db-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "bankingapp/rds/credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    dbname   = var.db_name
  })
}

resource "aws_db_instance" "postgres" {
  identifier             = "bankingapp-postgres"
  engine                 = "postgres"
  engine_version         = "16"  # PostgreSQL 16 (latest major version)
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  publicly_accessible    = false
  skip_final_snapshot    = true
  backup_retention_period = 1  # Changed from 7 to 1 for AWS Free Tier compatibility
  storage_encrypted      = true
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name
  apply_immediately      = true
}

resource "aws_lb" "app" {
  name               = "bankingapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "bankingapp-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "bankingapp-app-"
  image_id      = var.flask_ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/user_data_app.sh.tpl", {
    db_secret_arn = aws_secretsmanager_secret.db_credentials.arn
    db_host       = aws_db_instance.postgres.address
    db_name       = var.db_name
    db_username   = var.db_username
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "bankingapp-app"
      Project = "BankingApp"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "bankingapp-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "bankingapp-app"
    propagate_at_launch = true
  }
}

resource "aws_instance" "monitoring" {
  ami                         = var.monitoring_ami_id
  instance_type               = var.monitoring_instance_type
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  associate_public_ip_address = true

  tags = {
    Name    = "bankingapp-monitoring"
    Project = "BankingApp"
  }
}
