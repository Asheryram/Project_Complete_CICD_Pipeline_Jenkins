#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins setup at $(date)"

# Retrieve Jenkins admin password from Secrets Manager at runtime
echo "Retrieving Jenkins admin password from Secrets Manager..."
JENKINS_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)
echo "Jenkins admin password retrieved successfully"

# Update system
sudo yum update -y

# Install Docker and AWS CLI
sudo yum install -y docker aws-cli
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Node.js and Git on host (optional, for debugging)
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs git

# Get the Docker group ID from the host so the container can use the socket
DOCKER_GID=$$(getent group docker | cut -d: -f3)
echo "Docker GID: $${DOCKER_GID}"

# Set Docker socket permissions to be accessible
echo "Setting Docker socket permissions..."
sudo chmod 666 /var/run/docker.sock

# Create systemd service to fix Docker socket permissions on boot
echo "Creating systemd service for Docker socket permissions..."
sudo tee /etc/systemd/system/docker-socket-permissions.service > /dev/null <<'EOFSERVICE'
[Unit]
Description=Fix Docker socket permissions for Jenkins
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/chmod 666 /var/run/docker.sock
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSERVICE

sudo systemctl daemon-reload
sudo systemctl enable docker-socket-permissions.service
sudo systemctl start docker-socket-permissions.service

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
  -e JENKINS_ADMIN_PASSWORD="$${JENKINS_ADMIN_PASSWORD}" \
  jenkins/jenkins:lts

echo "Waiting for Jenkins container to start..."
sleep 45

# Verify Jenkins container is running
if ! sudo docker ps | grep -q jenkins; then
  echo "ERROR: Jenkins container failed to start"
  sudo docker logs jenkins
  exit 1
fi

# Verify Docker socket is mounted inside container
echo "Verifying Docker socket is accessible inside Jenkins container..."
if ! sudo docker exec jenkins test -S /var/run/docker.sock; then
  echo "ERROR: Docker socket not found inside Jenkins container"
  exit 1
fi
echo "Docker socket verified: OK"

# Install Docker CLI inside the Jenkins container so pipeline stages can run docker commands
echo "Installing Docker CLI inside Jenkins container..."
sudo docker exec -u root jenkins bash -c "
  apt-get update -qq &&
  apt-get install -y -qq docker.io &&
  docker --version &&
  echo 'Docker CLI installed successfully inside Jenkins container'
"

# Verify Docker CLI works inside container
echo "Verifying Docker works inside Jenkins container..."
if sudo docker exec jenkins docker ps > /dev/null 2>&1; then
  echo "Docker CLI verification: OK"
else
  echo "WARNING: Docker CLI installed but cannot connect to daemon"
  echo "Attempting to fix permissions..."
  sudo chmod 666 /var/run/docker.sock
  if sudo docker exec jenkins docker ps > /dev/null 2>&1; then
    echo "Docker CLI verification after permission fix: OK"
  else
    echo "ERROR: Docker CLI still cannot connect to daemon"
    exit 1
  fi
fi

# Install Node.js inside the Jenkins container (matches host version)
echo "Installing Node.js inside Jenkins container..."
sudo docker exec -u root jenkins bash -c "
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &&
  apt-get install -y nodejs &&
  node --version &&
  npm --version &&
  echo 'Node.js installed successfully inside Jenkins container'
"

# Clear the password from the environment
unset JENKINS_ADMIN_PASSWORD

# Final verification
echo "==================== SETUP SUMMARY ===================="
echo "Jenkins container: $(sudo docker ps --filter name=jenkins --format '{{.Status}}')"
echo "Docker socket permissions: $(ls -l /var/run/docker.sock)"
echo "Docker CLI in Jenkins: $(sudo docker exec jenkins docker --version)"
echo "Node.js in Jenkins: $(sudo docker exec jenkins node --version)"
echo "======================================================="

echo "Jenkins setup completed successfully at $(date)"
PUBLIC_IP=$$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Jenkins accessible at: http://$${PUBLIC_IP}:8080"
echo ""
echo "To get the initial admin password, run:"
echo "sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
