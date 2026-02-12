#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins setup at $(date)"

# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Node.js and Git on host (optional, for debugging)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs git

# Get the Docker group ID from the host so the container can use the socket
DOCKER_GID=$$(getent group docker | cut -d: -f3)

echo "Starting Jenkins container..."

# Run Jenkins in Docker
# --restart unless-stopped  → survives EC2 stop/start
# --user root               → needed to access /var/run/docker.sock on Amazon Linux
# --group-add $DOCKER_GID   → adds Jenkins to the host docker group
sudo docker run -d \
  -p 8080:8080 \
  -p 50000:50000 \
  --restart unless-stopped \
  --name jenkins \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --user root \
  --group-add "$${DOCKER_GID}" \
  jenkins/jenkins:lts

echo "Waiting for Jenkins container to start..."
sleep 30

# Install Docker CLI inside the Jenkins container so pipeline stages can run docker commands
echo "Installing Docker CLI inside Jenkins container..."
sudo docker exec jenkins bash -c "
  apt-get update -qq &&
  apt-get install -y -qq docker.io &&
  docker --version &&
  echo 'Docker CLI installed successfully inside Jenkins container'
"

# Install Node.js inside the Jenkins container (matches host version)
echo "Installing Node.js inside Jenkins container..."
sudo docker exec jenkins bash -c "
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash - &&
  apt-get install -y nodejs &&
  node --version &&
  npm --version &&
  echo 'Node.js installed successfully inside Jenkins container'
"

echo "Jenkins setup completed at $(date)"
echo "Jenkins should be accessible at http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"