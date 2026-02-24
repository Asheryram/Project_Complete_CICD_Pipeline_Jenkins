aws_region    = "eu-central-1"
project_name  = "jenkins-cicd-pipeline"
environment   = "dev"

vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.10.0/24", "10.0.20.0/24"]

allowed_ips = ["196.61.44.164/32"]  # Your trusted IP

jenkins_instance_type = "t3.small"
app_instance_type     = "t3.micro"

# NOTE: Set a real password here or pass via CLI: terraform apply -var='jenkins_admin_password=...'
# This password is now stored securely in AWS Secrets Manager (not in EC2 user data).
jenkins_admin_password = "your-secure-password-here"


grafana_admin_password   = "your-secure-password"
git_repo_url             = "https://github.com/Asheryram/Project_Complete_CICD_Pipeline_Jenkins.git"
monitoring_instance_type = "t3.micro"

# Email configuration for alertmanager
alert_email_to       = "ashertettehabotsi@gmail.com"
alert_email_from     = "ashertettehabotsi@gmail.com"
alert_email_username = "ashertettehabotsi@gmail.com"
alert_email_password = "gsbb tyfx bdtu kqjr"