#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/app-server-setup.log) 2>&1
echo "Starting app server setup at $(date)"

yum update -y
yum install -y docker git amazon-cloudwatch-agent

# Configure CloudWatch agent for Docker logs
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

# Start Docker service
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

systemctl enable amazon-cloudwatch-agent

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/app
chown ec2-user:ec2-user /opt/app


# Run Node Exporter for Prometheus scraping
docker run -d \
  --name node-exporter \
  --restart=unless-stopped \
  --network="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter:latest \
  --path.rootfs=/host \
  --web.listen-address=0.0.0.0:9100

echo "Node Exporter running on port 9100"
echo "App server setup completed at $(date)"