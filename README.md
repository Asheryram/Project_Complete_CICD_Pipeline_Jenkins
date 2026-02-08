# Complete CI/CD Pipeline with Jenkins

## Prerequisites

- AWS CLI installed and configured
- Terraform installed
- Git installed

## Setup Instructions

### 1. Configure AWS Credentials
```bash
aws configure
```
Enter your AWS Access Key ID, Secret Access Key, and default region.

### 2. Initialize Terraform
```bash
cd terraform
terraform init
```

### 3. Create terraform.tfvars
Create a `terraform.tfvars` file with your configuration:
```hcl
project_name = "your-project-name"
environment  = "dev"
region      = "us-east-1"
```

### 4. Plan and Apply Infrastructure
```bash
terraform plan
terraform apply
```

This will:
- Generate SSH key pair automatically
- Create AWS infrastructure
- Save private key as `{project_name}-{environment}-keypair.pem`
- Save public key as `{project_name}-{environment}-keypair.pub`

### 5. Set SSH Key Permissions
```bash
chmod 600 *.pem
```

### 6. Connect to EC2 Instance
```bash
ssh -i your-project-name-dev-keypair.pem ec2-user@<instance-ip>
```

### 7. Clean Up
```bash
terraform destroy
```

## Important Notes

- SSH keys are generated automatically by Terraform
- Never commit `.pem`, `.pub`, or `.tfvars` files to Git
- Keep your private key secure and never share it