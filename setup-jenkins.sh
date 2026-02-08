#!/bin/bash
# Install Jenkins on EC2 (run after Docker setup)

# Install Java
sudo yum install -y java-11-openjdk

# Add Jenkins repo and install
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum install -y jenkins

# Start Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Add jenkins user to docker group
sudo usermod -a -G docker jenkins
sudo systemctl restart jenkins

echo "Jenkins installed! Access it at http://YOUR_EC2_IP:8080"
echo "Initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword