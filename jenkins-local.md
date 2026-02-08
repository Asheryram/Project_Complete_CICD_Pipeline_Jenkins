# Run Jenkins locally with Docker

# 1. Pull and run Jenkins
docker run -d -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts

# 2. Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# 3. Access Jenkins at http://localhost:8080

# Note: You'll need to configure Jenkins to access your EC2 instance via SSH