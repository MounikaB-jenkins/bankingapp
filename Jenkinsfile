pipeline {
  agent any

  environment {
    AWS_REGION = 'ap-south-2'
    AWS_DEFAULT_REGION = 'ap-south-2'
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
          set -e
          sudo apt-get update -y
          sudo apt-get install -y unzip curl python3 python3-pip
          curl -fsSL https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip -o /tmp/terraform.zip
          unzip -o /tmp/terraform.zip -d /usr/local/bin
          curl -fsSL https://releases.hashicorp.com/packer/1.11.2/packer_1.11.2_linux_amd64.zip -o /tmp/packer.zip
          unzip -o /tmp/packer.zip -d /usr/local/bin
          python3 -m pip install --upgrade pip
        '''
      }
    }

    stage('Run Tests') {
      steps {
        sh '''
          set -e
          cd BankingApp
          python3 -m venv .venv
          . .venv/bin/activate
          pip install -r app/requirements.txt pytest
          pytest -q app/tests
        '''
      }
    }

    stage('Build AMIs') {
      steps {
        sh '''
          set -e
          cd BankingApp/packer
          packer init flask-app.pkr.hcl
          packer build -var "region=${AWS_REGION}" flask-app.pkr.hcl
          packer init monitoring.pkr.hcl
          packer build -var "region=${AWS_REGION}" monitoring.pkr.hcl
        '''
      }
    }

    stage('Deploy Infrastructure') {
      steps {
        sh '''
          set -e
          cd BankingApp/terraform
          terraform init
          terraform apply -auto-approve -var "region=${AWS_REGION}" -var "vpc_id=vpc-088237085ff583c8e" -var "subnet_ids=[\"subnet-0e2b2454962fb5acf\"]"
        '''
      }
    }
  }
}
