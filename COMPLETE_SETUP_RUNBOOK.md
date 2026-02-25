# Complete CI/CD Pipeline Setup Runbook

This runbook provides step-by-step instructions for anyone to set up the complete CI/CD pipeline with Jenkins, monitoring, and observability from scratch.

## 🏗️ Architecture Overview

```
Developer → GitHub → Jenkins (EC2+Docker) → Docker Hub → App Server (EC2)
                                                      ↓
                                              Monitoring Stack (EC2)
                                         [Prometheus + Grafana + Jaeger]
```

**What gets deployed:**
- **Jenkins Server**: Automated CI/CD pipeline with Docker-in-Docker
- **Application Server**: Node.js app with metrics and tracing
- **Monitoring Server**: Prometheus, Grafana, Alertmanager, Jaeger
- **Security**: CloudWatch logs, GuardDuty, encrypted S3 storage
- **Networking**: VPC with public/private subnets, security groups

## 📋 Prerequisites

### Required Tools
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip && sudo mv terraform /usr/local/bin/

# Verify installations
aws --version
terraform --version
```

### Required Accounts
1. **AWS Account** with programmatic access
2. **Docker Hub Account** with access token
3. **GitHub Repository** (fork this repo)
4. **Email Account** for alerts (Gmail with app password recommended)

### Get Your Public IP
```bash
curl ifconfig.me
# Note this IP - you'll need it for security configuration
```

## 🚀 Step 1: AWS Configuration

### Configure AWS CLI
```bash
aws configure
# AWS Access Key ID: [Your access key]
# AWS Secret Access Key: [Your secret key]
# Default region name: us-east-1
# Default output format: json
```

### Verify AWS Access
```bash
aws sts get-caller-identity
# Should return your account details
```

## 🔧 Step 2: Clone and Configure Repository

### Clone Repository
```bash
git clone https://github.com/YOUR_USERNAME/Project_Complete_CICD_Pipeline_Jenkins.git
cd Project_Complete_CICD_Pipeline_Jenkins
```

### Configure Terraform Variables
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
# AWS Configuration
aws_region = "eu-central-1"

# Project Configuration
project_name = "cicd-pipeline"
environment = "dev"

# Security Configuration - CRITICAL: Use your actual IP
allowed_ips = ["YOUR_IP_ADDRESS/32"]  # Replace with output from curl ifconfig.me

# Instance Types (adjust for budget)
jenkins_instance_type = "t3.small"    # Recommended minimum
app_instance_type = "t3.micro"
monitoring_instance_type = "t3.small"

# Jenkins Configuration
jenkins_admin_password = "YourSecurePassword123!"

# Monitoring Configuration
grafana_admin_password = "YourGrafanaPassword123!"
git_repo_url = "https://github.com/Asheryram/Project_Complete_CICD_Pipeline_Jenkins.git"

# Email Alert Configuration
alert_email_to = "alerts@yourcompany.com"
alert_email_from = "noreply@yourcompany.com"
alert_email_username = "your-email@gmail.com"
alert_email_password = "your-gmail-app-password"
```

## 🏗️ Step 3: Deploy Infrastructure

### Initialize Terraform
```bash
terraform init
```

### Plan Deployment
```bash
terraform plan
# Review the resources that will be created
```

### Deploy Infrastructure
```bash
terraform apply
# Type 'yes' when prompted
# Deployment takes ~5-10 minutes
```

### Save Important Outputs
```bash
terraform output > ../deployment-info.txt
cat ../deployment-info.txt
```

**Expected outputs:**
```
app_server_public_ip = "3.15.123.67"
app_server_private_ip = "10.0.2.45"
jenkins_public_ip = "18.191.45.123"
monitoring_server_public_ip = "3.15.234.89"
monitoring_server_private_ip = "10.0.1.249"
ssh_command_app = "ssh -i cicd-pipeline-dev-keypair.pem ec2-user@3.15.123.67"
ssh_command_jenkins = "ssh -i cicd-pipeline-dev-keypair.pem ec2-user@18.191.45.123"
```

## 🔐 Step 4: Access Jenkins

### Get Jenkins Initial Password
```bash
# SSH into Jenkins server
ssh -i cicd-pipeline-dev-keypair.pem ec2-user@JENKINS_PUBLIC_IP

# Get initial admin password
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
# Copy this password
```

### Complete Jenkins Setup
1. Open `http://JENKINS_PUBLIC_IP:8080`
2. Enter the initial admin password
3. Click "Install suggested plugins"
4. Create admin user:
   - Username: `admin`
   - Password: Use the password from terraform.tfvars
   - Full name: `Jenkins Admin`
   - Email: Your email

### Install Required Plugins
**Manage Jenkins → Plugins → Available Plugins**

Install these plugins:
- ✅ Docker Pipeline
- ✅ SSH Agent
- ✅ NodeJS
- ✅ Credentials Binding
- ✅ Pipeline: Stage View

## 🔑 Step 5: Configure Jenkins Credentials

### Add Docker Hub Credentials
1. **Manage Jenkins → Credentials → System → Global credentials**
2. **Add Credentials**:
   - Kind: `Username with password`
   - ID: `registry_creds`
   - Username: Your Docker Hub username
   - Password: Your Docker Hub access token
   - Description: `Docker Hub Registry`

### Add SSH Key for EC2 Deployment
1. **Add Credentials**:
   - Kind: `SSH Username with private key`
   - ID: `ec2_ssh`
   - Username: `ec2-user`
   - Private Key: **Enter directly** → Copy entire contents of `cicd-pipeline-dev-keypair.pem`
   - Description: `EC2 SSH Key`

## 🛠️ Step 6: Configure NodeJS Tool

1. **Manage Jenkins → Tools → NodeJS**
2. **Add NodeJS**:
   - Name: `nodejs-20`
   - Version: `NodeJS 20.x` (latest LTS)
   - Global npm packages: Leave empty
3. **Save**

## 📦 Step 7: Create Pipeline Job

### Create New Pipeline
1. **New Item** → Name: `cicd-pipeline` → **Pipeline** → OK
2. **General**:
   - ✅ This project is parameterized
   - Add String Parameter:
     - Name: `EC2_HOST`
     - Default Value: `10.0.2.45` (use your app_server_private_ip)
     - Description: `Private IP of the app server EC2 instance`
   - Add String Parameter:
     - Name: `JAEGER_ENDPOINT`
     - Default Value: `http://10.0.1.249:14268/api/traces` (use your monitoring_server_private_ip)
     - Description: `Jaeger collector endpoint for tracing`

### Configure Pipeline Source
3. **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `https://github.com/YOUR_USERNAME/Project_Complete_CICD_Pipeline_Jenkins.git`
   - Branch Specifier: `*/main`
   - Script Path: `Jenkinsfile`
4. **Save**

## 🧪 Step 8: Test the Pipeline

### Run First Build
1. **Build with Parameters**
2. Verify parameters:
   - EC2_HOST: Your app server private IP
   - JAEGER_ENDPOINT: Your Jaeger endpoint
3. **Build**

### Monitor Build Progress
Watch the pipeline stages:
1. ✅ Checkout - Clone repository
2. ✅ Install/Build - npm ci
3. ✅ Test - npm test
4. ✅ Docker Build - Build container image
5. ✅ Push Image - Push to Docker Hub
6. ✅ Deploy - Deploy to EC2 app server

### Verify Deployment
```bash
# Test application endpoints
APP_IP=$(terraform output -raw app_server_public_ip)
curl http://$APP_IP:5000/          # HTML page
curl http://$APP_IP:5000/health    # {"status":"healthy"}
curl http://$APP_IP:5000/api/info  # Version info
```

## 📊 Step 9: Access Monitoring Stack

### Get Monitoring URLs
```bash
MONITORING_IP=$(terraform output -raw monitoring_server_public_ip)
echo "Prometheus: http://$MONITORING_IP:9090"
echo "Grafana: http://$MONITORING_IP:3000"
echo "Alertmanager: http://$MONITORING_IP:9093"
echo "Jaeger: http://$MONITORING_IP:16686"
```

### Access Grafana
1. Open `http://MONITORING_IP:3000`
2. Login:
   - Username: `admin`
   - Password: Your grafana_admin_password from terraform.tfvars
3. Dashboards are pre-configured and ready to use

### Verify Metrics Collection
- **Prometheus**: Check targets at `http://MONITORING_IP:9090/targets`
- **Grafana**: View "Complete Observability Dashboard"
- **Jaeger**: Search for traces from service "timesheet-app"

## 🚦 Step 10: Generate Test Traffic

### Run Traffic Simulation
```bash
# Make script executable
chmod +x simulate-traffic.sh

# Generate realistic traffic for 5 minutes
./simulate-traffic.sh
```

This creates:
- HTTP requests to various endpoints
- Slow operations for performance testing
- Error conditions for alert testing
- Distributed traces in Jaeger

### Verify Observability
1. **Grafana**: See metrics in real-time dashboards
2. **Jaeger**: View distributed traces at `http://MONITORING_IP:16686`
3. **Prometheus**: Query metrics at `http://MONITORING_IP:9090`
4. **Alertmanager**: Check alerts at `http://MONITORING_IP:9093`

## 🔧 Step 11: Customize for Your Project

### Update Application Code
1. Modify `app.js` for your application logic
2. Update `package.json` dependencies
3. Modify `Dockerfile` if needed
4. Update tests in `app.test.js`

### Customize Monitoring
1. Edit `monitoring/prometheus.yml` for custom metrics
2. Modify Grafana dashboards in `monitoring/grafana-dashboards/`
3. Update alert rules in `monitoring/alert_rules.yml`

### Adjust Infrastructure
1. Modify `terraform/terraform.tfvars` for different instance sizes
2. Update security groups in `terraform/modules/security/main.tf`
3. Customize VPC settings in `terraform/modules/vpc/main.tf`

## 🚨 Troubleshooting Guide

### Common Issues and Solutions

#### 1. Jenkins Container Not Starting
```bash
# SSH into Jenkins server
ssh -i keypair.pem ec2-user@JENKINS_IP

# Check container status
sudo docker ps -a

# Check logs
sudo docker logs jenkins

# Restart if needed
sudo docker restart jenkins
```

#### 2. Pipeline Fails at Docker Build
**Error**: `docker: command not found`

**Solution**: Wait for Jenkins setup to complete (5-10 minutes after EC2 launch)

#### 3. SSH Deploy Fails
**Error**: `Permission denied (publickey)`

**Solution**: 
1. Verify `ec2_ssh` credential contains full `.pem` file content
2. Use private IP for EC2_HOST parameter, not public IP

#### 4. Application Not Accessible
```bash
# SSH into app server
ssh -i keypair.pem ec2-user@APP_IP

# Check container status
docker ps
docker logs node-app

# Check security group allows port 5000
```

#### 5. Monitoring Stack Not Working
```bash
# SSH into monitoring server
ssh -i keypair.pem ec2-user@MONITORING_IP

# Check docker-compose status
cd /opt/monitoring
sudo docker-compose ps
sudo docker-compose logs
```

### Performance Optimization

#### For Production Use
```hcl
# terraform.tfvars
jenkins_instance_type = "t3.medium"     # 2 vCPU, 4GB RAM
app_instance_type = "t3.small"          # 2 vCPU, 2GB RAM
monitoring_instance_type = "t3.medium"  # 2 vCPU, 4GB RAM
```

#### Cost Optimization
```bash
# Stop instances when not in use
aws ec2 stop-instances --instance-ids i-1234567890abcdef0

# Start instances when needed
aws ec2 start-instances --instance-ids i-1234567890abcdef0
```

## 🧹 Cleanup

### Destroy Infrastructure
```bash
cd terraform
terraform destroy
# Type 'yes' when prompted
```

### Verify Cleanup
```bash
# Check no resources remain
aws ec2 describe-instances --query 'Reservations[*].Instances[?State.Name!=`terminated`]'
aws s3 ls | grep cicd-pipeline
```


## 📚 Additional Resources

### Documentation
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Docker Hub Access Tokens](https://docs.docker.com/docker-hub/access-tokens/)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Grafana Dashboards](https://grafana.com/docs/grafana/latest/dashboards/)

### Monitoring Insights
- View `MONITORING_INSIGHTS_REPORT.md` for detailed observability analysis
- Check `screenshots/` folder for expected dashboard views
- Use `validate-observability.sh` to verify monitoring stack health

### Security Best Practices
1. **Never commit secrets**: Use `.gitignore` for `terraform.tfvars` and `.pem` files
2. **Rotate credentials**: Update Docker Hub tokens and passwords regularly
3. **Restrict IP access**: Always use your specific IP in `allowed_ips`
4. **Enable MFA**: Use AWS MFA for additional security
5. **Monitor logs**: Check CloudWatch logs regularly for suspicious activity

## 🎯 Success Criteria

Your setup is successful when:
- ✅ Jenkins pipeline runs without errors
- ✅ Application is accessible at `http://APP_IP:5000`
- ✅ Grafana shows metrics and dashboards
- ✅ Jaeger displays distributed traces
- ✅ Alerts are configured and working
- ✅ All security groups restrict access to your IP
- ✅ CloudWatch logs are streaming from all servers

## 🤝 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review logs in CloudWatch or via SSH
3. Verify all prerequisites are met
4. Ensure terraform.tfvars is correctly configured
5. Check AWS service limits and quotas

**Happy CI/CD Pipeline Building! 🚀**