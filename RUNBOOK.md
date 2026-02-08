# CI/CD Pipeline Runbook

## Quick Start Guide

### Step 1: EC2 Setup (5 minutes)

```bash
# Connect to EC2
ssh -i your-key.pem ec2-user@<EC2_IP>

# Install Docker
sudo yum update -y && sudo yum install docker -y
sudo systemctl start docker && sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Logout and login again
exit
ssh -i your-key.pem ec2-user@<EC2_IP>

# Verify Docker
docker --version
```

### Step 2: Jenkins Credentials (3 minutes)

**Jenkins → Manage Jenkins → Credentials → Global → Add Credentials**

1. **registry_creds**
   - Type: Username with password
   - Username: `<dockerhub-username>`
   - Password: `<dockerhub-password>`
   - ID: `registry_creds`

2. **ec2_ssh**
   - Type: SSH Username with private key
   - Username: `ec2-user`
   - Private Key: Enter directly (paste .pem content)
   - ID: `ec2_ssh`

### Step 3: Create Pipeline (2 minutes)

1. Jenkins Dashboard → New Item
2. Name: `CICD-Flask-Pipeline`
3. Type: Pipeline → OK
4. Configuration:
   - **Pipeline section**:
     - Definition: Pipeline script from SCM
     - SCM: Git
     - Repository URL: `https://github.com/<your-username>/<repo-name>.git`
     - Branch: `*/main`
     - Script Path: `Jenkinsfile`
   
5. **Add Parameter**:
   - Check "This project is parameterized"
   - Add String Parameter:
     - Name: `EC2_HOST`
     - Default: `<your-ec2-public-ip>`

6. Save

### Step 4: Run Pipeline (1 minute)

1. Click "Build Now"
2. Monitor Console Output
3. Wait for SUCCESS

### Step 5: Verify (1 minute)

```bash
# Test endpoints
curl http://<EC2_IP>:5000/
curl http://<EC2_IP>:5000/health

# Or browser
http://<EC2_IP>:5000/
```

## Pipeline Stages Explained

| Stage | Duration | Action | Output |
|-------|----------|--------|--------|
| Checkout | ~10s | Clone Git repo | Source code |
| Install/Build | ~20s | Install Python deps | Dependencies ready |
| Test | ~5s | Run unit tests | Test results |
| Docker Build | ~30s | Build image | Docker image |
| Push Image | ~40s | Push to registry | Image in registry |
| Deploy | ~30s | SSH deploy to EC2 | Running container |

**Total Time**: ~2-3 minutes

## Common Issues & Solutions

### Issue 1: "Permission denied" on EC2
```bash
# Solution: Add Jenkins public key to EC2
# Or ensure ec2_ssh credential has correct private key
```

### Issue 2: "Cannot connect to Docker daemon"
```bash
# On Jenkins server
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Issue 3: Port 5000 not accessible
```bash
# Check EC2 Security Group
# Add Inbound Rule: Custom TCP, Port 5000, Source 0.0.0.0/0
```

### Issue 4: Docker login fails
```bash
# Verify credentials in Jenkins
# Test manually: docker login -u <username>
```

## Monitoring & Logs

### Check container on EC2
```bash
ssh ec2-user@<EC2_IP>
docker ps
docker logs flask-app
```

### Jenkins Console Output
- Click on build number → Console Output

### Application Logs
```bash
docker logs -f flask-app
```

## Rollback Procedure

```bash
# SSH to EC2
ssh ec2-user@<EC2_IP>

# Stop current container
docker stop flask-app && docker rm flask-app

# Run previous version
docker run -d --name flask-app -p 5000:5000 <username>/cicd-flask-app:<previous-build-number>
```

## Cleanup Commands

### On EC2
```bash
# Stop and remove container
docker stop flask-app && docker rm flask-app

# Remove all images
docker rmi $(docker images -q)

# Full cleanup
docker system prune -af
```

### On Jenkins Server
```bash
# Remove workspace
rm -rf /var/lib/jenkins/workspace/CICD-Flask-Pipeline

# Clean Docker
docker system prune -af
```

## Security Checklist

- [ ] EC2 security group restricts SSH to your IP
- [ ] Docker registry credentials stored securely in Jenkins
- [ ] EC2 private key not committed to Git
- [ ] Application runs as non-root user
- [ ] Regular security updates on EC2

## Performance Optimization

1. **Use Docker layer caching** - Already implemented in Dockerfile
2. **Parallel stages** - Can be added for independent tasks
3. **Artifact caching** - Use Jenkins artifact storage
4. **Multi-stage builds** - Reduce image size

## Maintenance

### Weekly
- Check Jenkins disk space
- Review pipeline logs
- Update dependencies

### Monthly
- Update Jenkins plugins
- Patch EC2 instance
- Rotate credentials

## Evidence Collection

### Screenshots to capture:
1. Jenkins pipeline success (Blue Ocean view)
2. Console output showing all stages
3. Docker Hub showing pushed image
4. Browser showing application response
5. EC2 terminal showing running container

### Logs to save:
```bash
# Jenkins console output
# Save from Jenkins UI

# EC2 container logs
docker logs flask-app > deployment-logs.txt

# Docker images
docker images > docker-images.txt
```

## Contact & Support

- Jenkins Documentation: https://www.jenkins.io/doc/
- Docker Documentation: https://docs.docker.com/
- Flask Documentation: https://flask.palletsprojects.com/
- AWS EC2 Documentation: https://docs.aws.amazon.com/ec2/
