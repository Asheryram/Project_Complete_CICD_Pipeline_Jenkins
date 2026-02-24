#!/bin/bash
# monitoring-setup.sh  –  Terraform templatefile
#
# Template variables injected by Terraform:
#   ${app_server_ip}        – private IP of the app EC2 instance
#   ${grafana_admin_password} – Grafana admin password (from TF variable)
#   ${git_repo_url}         – HTTPS URL of this git repository
#   ${alert_email_password} – Email password for alertmanager
#   ${alert_email_to}       – Email address to send alerts to
#   ${alert_email_from}     – Email address to send alerts from
#   ${alert_email_username} – Email username for SMTP authentication
#
# All shell variables use single $ in this script

set -e
exec > >(tee /var/log/monitoring-setup.log) 2>&1
echo "=== Starting monitoring server setup at $(date) ==="

# ── 1. System packages ────────────────────────────────────────────────────
yum update -y
yum install -y docker git amazon-cloudwatch-agent

# ── 2. Configure CloudWatch agent ─────────────────────────────────────────
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

# ── 3. Docker service ─────────────────────────────────────────────────────
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

systemctl enable amazon-cloudwatch-agent

# ── 4. Docker Compose ─────────────────────────────────────────────────────
COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": *"\(.*\)".*/\1/')
curl -fsSL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# ── 5. Clone repository (gets dashboard JSON and config templates) ─────────
git clone ${git_repo_url} /opt/monitoring-repo
chown -R ec2-user:ec2-user /opt/monitoring-repo

MONITORING_DIR=/opt/monitoring-repo/monitoring

# ── 6. Write .env file (runtime variables for docker-compose) ─────────────
#    IMPORTANT: do not use # or $ in the password value.
cat > "$MONITORING_DIR/.env" <<'ENVEOF'
APP_SERVER_IP=${app_server_ip}
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
ALERT_EMAIL_TO=${alert_email_to}
ALERT_EMAIL_FROM=${alert_email_from}
ALERT_EMAIL_USERNAME=${alert_email_username}
ALERT_EMAIL_PASSWORD=${alert_email_password}
ENVEOF

chown ec2-user:ec2-user "$MONITORING_DIR/.env"
chmod 600 "$MONITORING_DIR/.env"

# ── 7. Process alertmanager template ──────────────────────────────────────
envsubst < "$MONITORING_DIR/alertmanager.yml.template" > "$MONITORING_DIR/alertmanager.yml"

# ── 8. Start the monitoring stack ─────────────────────────────────────────
# Run as ec2-user so volume-mounted files are owned correctly
su -c "cd $MONITORING_DIR && docker-compose up -d" ec2-user

echo "=== Monitoring stack started at $(date) ==="
echo "  Grafana:      http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "  Prometheus:   http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "  Alertmanager: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9093"
