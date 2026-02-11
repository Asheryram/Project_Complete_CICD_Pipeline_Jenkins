#!/bin/bash
# Install Jenkins on EC2 using Docker

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Run Jenkins in Docker
sudo docker run -d -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
sleep 30

echo "Jenkins installed! Access it at http://YOUR_EC2_IP:8080"
echo "Initial admin password:"
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword