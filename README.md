# BankingApp

This project creates a banking-style AWS reference architecture on the free tier using immutable infrastructure principles.

## What it provisions
- Flask application AMI built by Packer
- Monitoring AMI with Prometheus and Grafana built by Packer
- Terraform-managed EC2 app fleet behind an Application Load Balancer
- Auto Scaling Group for app instances
- PostgreSQL RDS instance
- Secrets Manager secret for database credentials
- Monitoring instance with Prometheus and Grafana

## Architecture
1. Packer builds a Flask AMI and a monitoring AMI.
2. Terraform launches the app instances from the Flask AMI and uses an ALB + ASG for scaling.
3. Terraform provisions a PostgreSQL RDS instance and stores credentials in Secrets Manager.
4. The monitoring instance runs Prometheus/Grafana and can scrape app instances.

## Prerequisites
- AWS CLI configured
- Terraform installed
- Packer installed
- Python 3.11+

## Quick start
1. Copy the sample Terraform variables file:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```
2. **CRITICAL:** Edit `terraform/terraform.tfvars` and set `trusted_ip_cidr` to the public IP address of the machine you are deploying from (e.g., your local machine or your Jenkins agent's NAT Gateway). You can find your IP by searching "what is my IP" in Google. The format must be `"your_ip/32"`. This is essential for security.
3. Run:
   ```bash
   bash scripts/deploy.sh
   ```

## Jenkins one-click deployment
1. Create a new Jenkins Pipeline job.
2. Point it to this repository and set the pipeline script path to `BankingApp/Jenkinsfile`.
3. Run the job once to build the AMIs and deploy the full BankingApp stack.
4. The Jenkins job will:
   - install Terraform and Packer
   - run the Python tests
   - build the Flask and monitoring AMIs
   - deploy the infrastructure with Terraform, automatically using the new AMI IDs
   - initialize the database with sample data

## Notes
- The default region is eu-central-1.
- The default VPC and subnet values are set to the requested values from the earlier deployment context.
- The Jenkins pipeline automatically handles passing AMI IDs to Terraform. For manual deployment with `deploy.sh`, you will need to update `terraform.tfvars` yourself.
- **Security Warning:** The default `trusted_ip_cidr` in `variables.tf` is `0.0.0.0/0`, which is insecure. Always override this in `terraform.tfvars` to lock down SSH, monitoring, and database initialization access to your specific IP address.
