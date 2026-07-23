pipeline {
  agent any

  environment {
    AWS_REGION = 'eu-central-1'
    AWS_DEFAULT_REGION = 'eu-central-1'
    AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
    AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
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
          export PYTHONPATH=$PYTHONPATH:.
          pytest -q app/tests
        '''
      }
    }

    stage('Build AMIs') {
      steps {
        sh '''
          set -e
          cd packer
          packer init flask-app.pkr.hcl
          packer build -var "region=${AWS_REGION}" flask-app.pkr.hcl | tee flask-build.log
          packer init monitoring.pkr.hcl
          packer build -var "region=${AWS_REGION}" monitoring.pkr.hcl | tee monitoring-build.log
        '''
      }
    }

    stage('Extract AMI IDs') {
      steps {
        sh '''
          set -e
          cd packer
          FLASK_AMI=$(grep -o "ami-[a-z0-9]\{17\}" flask-build.log | head -1)
          MONITORING_AMI=$(grep -o "ami-[a-z0-9]\{17\}" monitoring-build.log | head -1)
          
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
          source ../ami_ids.env
          terraform apply -auto-approve \
            -var "region=${AWS_REGION}" \
            -var "flask_ami_id=$FLASK_AMI" \
            -var "monitoring_ami_id=$MONITORING_AMI"
        '''
      }
    }
  }
}
