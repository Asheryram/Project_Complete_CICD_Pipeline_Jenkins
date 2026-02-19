#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins setup at $(date)"

# ── 1. Retrieve Jenkins admin password from Secrets Manager ──────────────────
echo "Retrieving Jenkins admin password from Secrets Manager..."
JENKINS_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)
echo "Jenkins admin password retrieved successfully"

# ── 2. System update ─────────────────────────────────────────────────────────
sudo yum update -y

# ── 3. Install Java 21 (required by Jenkins) ─────────────────────────────────
# Amazon Linux 2 ships Amazon Corretto via amazon-linux-extras
sudo amazon-linux-extras enable corretto21
sudo yum install -y java-21-amazon-corretto fontconfig
java -version

# ── 4. Add Jenkins LTS repository and install Jenkins ────────────────────────
# Official RHEL/yum instructions from https://www.jenkins.io/doc/book/installing/linux/
sudo wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/rpm-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2023.key

sudo yum upgrade -y
sudo yum install -y jenkins
sudo systemctl daemon-reload

# ── 5. Install Docker (for Jenkins pipeline stages) ──────────────────────────
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker

# Add jenkins and ec2-user to the docker group so pipelines can run containers
sudo usermod -a -G docker jenkins
sudo usermod -a -G docker ec2-user

# ── 6. Install Node.js 20 and Git ────────────────────────────────────────────
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs git
node --version
npm --version

# ── 7. Pre-set the Jenkins admin password via Groovy init script ─────────────
# Jenkins executes .groovy files in $JENKINS_HOME/init.groovy.d/ at startup.
# This sets the admin password so the setup wizard is skipped automatically.
sudo mkdir -p /var/lib/jenkins/init.groovy.d

sudo tee /var/lib/jenkins/init.groovy.d/set-admin-password.groovy > /dev/null <<GROOVY
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "${r"${JENKINS_ADMIN_PASSWORD}"}")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
GROOVY

# Substitute the actual password value into the Groovy script
sudo sed -i "s|\\\${JENKINS_ADMIN_PASSWORD}|$${JENKINS_ADMIN_PASSWORD}|g" \
  /var/lib/jenkins/init.groovy.d/set-admin-password.groovy

sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

# Clear the password from the environment now that the script is written
unset JENKINS_ADMIN_PASSWORD

# ── 8. Enable and start Jenkins ───────────────────────────────────────────────
sudo systemctl enable jenkins
sudo systemctl start jenkins

# ── 9. Wait for Jenkins to become ready ──────────────────────────────────────
echo "Waiting for Jenkins to start..."
for i in $(seq 1 24); do
  if sudo systemctl is-active --quiet jenkins; then
    if curl -s -o /dev/null -w "%%{http_code}" http://localhost:8080/login | grep -qE "^(200|403)"; then
      echo "Jenkins is up (attempt $${i})"
      break
    fi
  fi
  echo "Attempt $${i}/24 – waiting 10s..."
  sleep 10
done

# ── 10. Final status check ────────────────────────────────────────────────────
if ! sudo systemctl is-active --quiet jenkins; then
  echo "ERROR: Jenkins service failed to start"
  sudo journalctl -u jenkins --no-pager -n 50
  exit 1
fi

echo "==================== SETUP SUMMARY ===================="
echo "Jenkins service:  $(sudo systemctl is-active jenkins)"
echo "Java version:     $(java -version 2>&1 | head -1)"
echo "Node.js version:  $(node --version)"
echo "Docker version:   $(docker --version)"
echo "======================================================="

echo "Jenkins setup completed successfully at $(date)"
PUBLIC_IP=$$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Jenkins accessible at: http://$${PUBLIC_IP}:8080"
echo ""
echo "To retrieve the initial admin password if needed:"
echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
