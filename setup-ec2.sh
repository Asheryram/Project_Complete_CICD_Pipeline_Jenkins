#!/bin/bash
# Run this on your EC2 instance to install Docker

sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

echo "Docker installed! Please logout and login again for group changes to take effect."