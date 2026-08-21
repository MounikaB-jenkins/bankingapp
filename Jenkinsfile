pipeline {
  agent any

  environment {
    AWS_REGION = 'eu-central-1'
    AWS_DEFAULT_REGION = 'eu-central-1'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Environment') {
      steps {
        sh '''
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive
          export PATH="$HOME/bin:$PATH"

          if [ "$(id -u)" -eq 0 ]; then
            SUDO=""
          elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
            SUDO="sudo"
          else
            SUDO=""
          fi

          if command -v apt-get >/dev/null 2>&1; then
            if [ -n "$SUDO" ]; then
              "$SUDO" apt-get update -y
              "$SUDO" apt-get install -y unzip curl python3 python3-pip python3-venv
            else
              apt-get update -y
              apt-get install -y unzip curl python3 python3-pip python3-venv
            fi
          fi

          mkdir -p "$HOME/bin"

          if ! command -v terraform >/dev/null 2>&1; then
            curl -fsSL https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip -o /tmp/terraform.zip
            unzip -o /tmp/terraform.zip -d "$HOME/bin"
            chmod +x "$HOME/bin/terraform"
          fi

          if ! command -v packer >/dev/null 2>&1; then
            curl -fsSL https://releases.hashicorp.com/packer/1.11.2/packer_1.11.2_linux_amd64.zip -o /tmp/packer.zip
            unzip -o /tmp/packer.zip -d "$HOME/bin"
            chmod +x "$HOME/bin/packer"
          fi

          python3 -m pip install --upgrade pip
        '''
      }
    }

    stage('Run Tests') {
      steps {
        sh '''
          set -e
          python3 -m venv .venv
          . .venv/bin/activate
          pip install -r app/requirements.txt pytest
          export PYTHONPATH=$PYTHONPATH:$(pwd)
          pytest -q app/tests
        '''
      }
    }

    stage('Prepare VPC') {
      steps {
        sh '''
          set -e
          CREATE_VPC=$(grep create_vpc terraform/terraform.tfvars | grep -v '^#' | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
          if [ "$CREATE_VPC" = "true" ]; then
            source ./scripts/create-default-vpc.sh
            # Get SUBNET_IDS from the script output (all subnets)
            SUBNET_IDS=$(echo "$SUBNET_IDS" | tr ',' ' ')
          else
            VPC_ID=$(grep vpc_id terraform/terraform.tfvars | grep -v '^#' | awk -F= '{gsub(/[\" ]/, "", $2); print $2}')
            SUBNET_IDS_RAW=$(grep subnet_ids terraform/terraform.tfvars | grep -v '^#' | awk -F= '{print $2}')
            SUBNET_ID=$(echo "$SUBNET_IDS_RAW" | tr -d '[" ]' | cut -d, -f1)
            SUBNET_IDS=$(echo "$SUBNET_IDS_RAW" | tr -d '[" ]')
          fi
          echo "VPC_ID=$VPC_ID" > vpc_info.env
          echo "SUBNET_ID=$SUBNET_ID" >> vpc_info.env
          echo "SUBNET_IDS=$SUBNET_IDS" >> vpc_info.env
        '''
      }
    }

    stage('Build AMIs') {
      steps {
        sh '''
          set -e
          set -o pipefail
          
          # Load VPC info from previous stage
          source vpc_info.env
          
          if [ -z "$VPC_ID" ] || [ -z "$SUBNET_ID" ]; then
            echo "ERROR: VPC_ID and SUBNET_ID not found. Prepare VPC stage failed."
            exit 1
          fi
          
          cd packer
          packer init flask-app.pkr.hcl
          packer build -var "region=${AWS_REGION}" -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}" flask-app.pkr.hcl | tee flask-build.log
          packer init monitoring.pkr.hcl
          packer build -var "region=${AWS_REGION}" -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}" monitoring.pkr.hcl | tee monitoring-build.log
        '''
      }
    }

    stage('Extract AMI IDs') {
      steps {
        sh '''
          set -e
          cd packer
          FLASK_AMI=$(grep -oE "ami-[a-z0-9]{17}" flask-build.log | tail -1)
          MONITORING_AMI=$(grep -oE "ami-[a-z0-9]{17}" monitoring-build.log | tail -1)
          
          if [ -z "$FLASK_AMI" ] || [ -z "$MONITORING_AMI" ]; then
            echo "ERROR: Could not extract AMI IDs from Packer output"
            exit 1
          fi
          
          echo "FLASK_AMI=$FLASK_AMI" > ../ami_ids.env
          echo "MONITORING_AMI=$MONITORING_AMI" >> ../ami_ids.env
          echo "Extracted AMI IDs:"
          echo "  Flask AMI: $FLASK_AMI"
          echo "  Monitoring AMI: $MONITORING_AMI"
        '''
      }
    }

    stage('Deploy Infrastructure') {
      steps {
        sh '''
          set -e
          cd terraform
          terraform init
          
          # Load VPC info and AMI IDs
          source ../vpc_info.env
          source ../ami_ids.env
          
          # Clean up any existing resources that might conflict
          terraform destroy -auto-approve -var "region=${AWS_REGION}" || true
          
          # Deploy with create_vpc=false since VPC already exists from Prepare VPC stage
          # Build HCL list from comma-separated SUBNET_IDS
          SUBNET_IDS_HCL=""
          IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
          for i in "${!SUBNET_ARRAY[@]}"; do
            if [ $i -eq 0 ]; then
              SUBNET_IDS_HCL="\"${SUBNET_ARRAY[$i]}\""
            else
              SUBNET_IDS_HCL="$SUBNET_IDS_HCL, \"${SUBNET_ARRAY[$i]}\""
            fi
          done
          
          cat > terraform.tfvars.auto <<EOF
region = "${AWS_REGION}"
create_vpc = false
vpc_id = "$VPC_ID"
subnet_ids = [$SUBNET_IDS_HCL]
flask_ami_id = "$FLASK_AMI"
monitoring_ami_id = "$MONITORING_AMI"
EOF
          terraform apply -auto-approve -var-file=terraform.tfvars.auto
        '''
      }
      post {
        always {
          sh '''
            cd terraform
            echo "Saving Terraform outputs..."
            # Only save secret_arn if it exists in the state
            if terraform output -raw secret_arn > /dev/null 2>&1; then
              terraform output -raw secret_arn > ../db_secret_arn.txt
            else
              echo "secret_arn output not available (apply may have failed)"
              # Create empty file so downstream stages don't fail
              touch ../db_secret_arn.txt
            fi
          '''
        }
      }
    }

    stage('Initialize Database') {
      steps {
        sh '''
          set -e
          . .venv/bin/activate
          pip install boto3 psycopg2-binary
          # Only run DB init if secret_arn was saved (infrastructure deployed successfully)
          SECRET_ARN=$(cat db_secret_arn.txt)
          if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != " " ]; then
            python3 scripts/run_db_init.py "$SECRET_ARN" "scripts/init_db.sql"
          else
            echo "Skipping database initialization - infrastructure deployment may have failed"
          fi
        '''
      }
    }
  }
}