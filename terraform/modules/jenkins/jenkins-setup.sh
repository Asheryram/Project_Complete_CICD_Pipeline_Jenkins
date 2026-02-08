#!/bin/bash
set -e  # Exit on any error

# Log all output
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins setup at $(date)"

# Update system
echo "Updating system..."
yum update -y

# Install Docker using amazon-linux-extras
echo "Installing Docker..."
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Java 11 (Amazon Linux 2 packages)
echo "Installing Java..."
amazon-linux-extras install java-openjdk11 -y

# Verify Java installation
java -version
echo "JAVA_HOME: $JAVA_HOME"

# Add Jenkins repository and install
echo "Adding Jenkins repository..."
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

echo "Installing Jenkins..."
yum install -y jenkins

# Add jenkins user to docker group
echo "Adding jenkins user to docker group..."
usermod -a -G docker jenkins

# Configure Jenkins admin password
echo "Configuring Jenkins..."
mkdir -p /var/lib/jenkins/init.groovy.d
cat > /var/lib/jenkins/init.groovy.d/basic-security.groovy << 'EOF'
#!groovy
import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "${jenkins_admin_password}")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()

Jenkins.instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)
EOF

# Start Jenkins
echo "Starting Jenkins service..."
systemctl start jenkins
systemctl enable jenkins

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
sleep 30

# Check Jenkins status
systemctl status jenkins

# Install additional tools
echo "Installing additional tools..."
yum install -y git

echo "Jenkins setup completed at $(date)!"