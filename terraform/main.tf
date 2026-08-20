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

# Optional VPC/subnet creation when migrating to a new account
resource "aws_vpc" "default" {
  count     = var.create_vpc ? 1 : 0
  cidr_block = var.vpc_cidr
  tags = {
    Name    = "bankingapp-vpc"
    Project = "BankingApp"
  }
}

resource "aws_subnet" "private" {
  count = var.create_vpc ? length(var.subnet_cidrs) : 0
  vpc_id = aws_vpc.default[0].id
  cidr_block = var.subnet_cidrs[count.index]
  tags = {
    Name    = "bankingapp-subnet-${count.index + 1}"
    Project = "BankingApp"
  }
}

locals {
  effective_vpc_id = var.create_vpc ? aws_vpc.default[0].id : var.vpc_id
  effective_subnet_ids = var.create_vpc ? [for s in aws_subnet.private : s.id] : var.subnet_ids
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#%^*-_"  # Removed @ which is not allowed by RDS
}

resource "aws_security_group" "app" {
  name        = "bankingapp-app-sg"
  description = "Allow app traffic"
  vpc_id      = local.effective_vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    # Allow traffic from the ALB
    security_groups = [aws_security_group.alb.id]
  }

  # Allow Node Exporter scraping from monitoring instance
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name        = "bankingapp-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = local.effective_vpc_id

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
  vpc_id      = local.effective_vpc_id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_ip_cidr
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.trusted_ip_cidr
  }

  # Alertmanager
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = var.trusted_ip_cidr
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.trusted_ip_cidr
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
  vpc_id      = local.effective_vpc_id

  # Allow access from the app instances and the trusted IP for initialization
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    cidr_blocks     = var.trusted_ip_cidr
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
  subnet_ids = local.effective_subnet_ids
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
  # Changing the identifier forces a replacement of the RDS instance. This is
  # necessary because an in-place major version downgrade is not allowed by AWS.
  identifier             = "bankingapp-postgres-v14"
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  # Set to true to allow initialization from outside the VPC (e.g., Jenkins).
  # For production, this should be 'false' and initialization should be handled from within the VPC.
  publicly_accessible    = true
  # A backup_retention_period > 0 enables Point-in-Time Recovery (PITR).
  # 7 days is a reasonable default, but we are setting it to 1 to stay within
  # the AWS Free Tier limits, which may not allow for longer retention periods.
  backup_retention_period = 1
  # Create a final snapshot on deletion to prevent data loss.
  skip_final_snapshot    = false
  storage_encrypted      = true
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name
  # Define specific windows for backups and maintenance to avoid performance impact during peak hours.
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  apply_immediately      = false # Apply changes during the next maintenance window.
}

resource "aws_iam_role" "app_instance_role" {
  name = "bankingapp-app-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "secrets_manager_read_policy" {
  name        = "bankingapp-secrets-manager-read-policy"
  description = "Allows reading the database credentials secret"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue"
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_secrets_policy" {
  role       = aws_iam_role.app_instance_role.name
  policy_arn = aws_iam_policy.secrets_manager_read_policy.arn
}

resource "aws_iam_role" "monitoring_instance_role" {
  name = "bankingapp-monitoring-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_discovery_policy" {
  name        = "bankingapp-ec2-discovery-policy"
  description = "Allows describing EC2 instances for Prometheus service discovery"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ec2_discovery_policy" {
  role       = aws_iam_role.monitoring_instance_role.name
  policy_arn = aws_iam_policy.ec2_discovery_policy.arn
}

resource "aws_lb" "app" {
  name               = "bankingapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.effective_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "bankingapp-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = local.effective_vpc_id
  health_check {
    path = "/health"
    matcher = "200"
    # Give the app more time to start and connect to the DB before failing the health check.
    # The default timeout of 5s is too aggressive for an app with dependencies.
    interval            = 30
    timeout             = 15
    healthy_threshold   = 3
    unhealthy_threshold = 3
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
  # vpc_security_group_ids is deprecated when network_interfaces is used.
  # We add this block to ensure instances get a public IP, allowing them to
  # reach the AWS Secrets Manager endpoint.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.app_instance_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data_app.sh.tpl", {
    db_secret_arn = aws_secretsmanager_secret.db_credentials.arn
    aws_region    = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "bankingapp-app"
      Project = "BankingApp"
    }
  }
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "bankingapp-app-instance-profile"
  role = aws_iam_role.app_instance_role.name
}

resource "aws_iam_instance_profile" "monitoring_instance_profile" {
  name = "bankingapp-monitoring-instance-profile"
  role = aws_iam_role.monitoring_instance_role.name
}

resource "aws_autoscaling_group" "app" {
  name                = "bankingapp-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = local.effective_subnet_ids
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
  subnet_id                   = local.effective_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.monitoring_instance_profile.name

  tags = {
    Name    = "bankingapp-monitoring"
    Project = "BankingApp"
  }
}
