#!/bin/bash
set -e
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins Docker setup at $(date)"

# Install Docker and CloudWatch agent
sudo yum update -y
sudo yum install -y docker git amazon-cloudwatch-agent

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/docker.log",
            "log_group_name": "/aws/ec2/docker",
            "log_stream_name": "{instance_id}/docker"
          }
        ]
      }
    }
  }
}
EOF

# Configure Docker to log to CloudWatch
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOFCONFIG
{
  "log-driver": "awslogs",
  "log-opts": {
    "awslogs-region": "$AWS_REGION",
    "awslogs-group": "/aws/ec2/docker-containers",
    "awslogs-create-group": "true"
  }
}
EOFCONFIG

sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

sudo systemctl enable amazon-cloudwatch-agent

# Create Docker network
sudo docker network create jenkins || true

# Run Docker-in-Docker container
sudo docker run --name jenkins-docker --rm --detach \
  --privileged --network jenkins --network-alias docker \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 2376:2376 \
  docker:dind --storage-driver overlay2

# Build custom Jenkins image with Docker CLI
echo "Building custom Jenkins image with Docker CLI..."
sudo docker build -t jenkins-with-docker - <<'EOF'
FROM jenkins/jenkins:2.541.2-jdk21
USER root

# Install Docker CLI
RUN apt-get update && \
    apt-get install -y docker.io && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Jenkins plugins
RUN jenkins-plugin-cli --plugins \
    git \
    workflow-aggregator \
    docker-workflow \
    docker-plugin \
    nodejs \
    credentials-binding \
    pipeline-stage-view \
    blueocean \
    configuration-as-code

USER jenkins
EOF

# Run Jenkins container with custom image
echo "Starting Jenkins container..."
sudo docker run --name jenkins --restart=on-failure --detach \
  --network jenkins \
  --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client \
  --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  jenkins-with-docker

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
for i in $(seq 1 30); do
  if curl -s http://localhost:8080 > /dev/null; then
    echo "Jenkins is up!"
    break
  fi
  echo "Attempt $i/30 - waiting 10s..."
  sleep 10
done

# Print initial admin password
echo "Waiting for initial admin password to be generated..."
sleep 30
echo "==================== JENKINS ADMIN PASSWORD ===================="
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword || echo "Password not yet available - check manually later"
echo "================================================================"

echo "==================== SETUP SUMMARY ===================="
echo "Jenkins running in Docker with Docker CLI installed"
echo "Docker version: $(docker --version)"
echo "======================================================="
echo "Jenkins setup completed at $(date)"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Jenkins accessible at: http://$PUBLIC_IP:8080"
echo ""
echo "Get initial admin password:"
echo "  sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"