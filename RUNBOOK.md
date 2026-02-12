Here's the complete updated runbook with all the troubleshooting fixes:

```markdown
# CI/CD Pipeline with Jenkins — Runbook

> **Stack:** Node.js app · Jenkins in Docker on EC2 · Docker Hub · SSH deploy
>
> ⚠️ **IP addresses change on every EC2 restart.** Check `infrastructure-outputs.txt` (or run `terraform output`) for the current IPs before each session. Replace `<JENKINS_IP>` and `<APP_IP>` throughout this guide with those values.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Structure](#2-repository-structure)
3. [Jenkins Server — First-Time Setup](#3-jenkins-server--first-time-setup)
4. [Configure the App Server](#4-configure-the-app-server)
5. [Get the Initial Admin Password](#5-get-the-initial-admin-password)
6. [Install Jenkins Plugins](#6-install-jenkins-plugins)
7. [Add Jenkins Credentials](#7-add-jenkins-credentials)
8. [Create the Pipeline Job](#8-create-the-pipeline-job)
9. [Run the Pipeline](#9-run-the-pipeline)
10. [Verify Deployment](#10-verify-deployment)
11. [Updating the App Server IP](#11-updating-the-app-server-ip)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Architecture Overview

```
Developer → GitHub → Jenkins container (EC2 <JENKINS_IP>:8080)
                              │
                        Pipeline Stages:
                        1. Checkout
                        2. Install (npm ci)
                        3. Test (npm test)
                        4. Docker Build & Tag
                        5. Push to Docker Hub
                        6. SSH Deploy → App Server (EC2 <APP_IP>)
                                              │
                                         Node App :5000
```

Get your current IPs before starting:

```bash
cat infrastructure-outputs.txt
# or
cd terraform && terraform output
```

---

## 2. Repository Structure

```
.
├── app.js                  # Node.js application
├── app.test.js             # Tests
├── package.json            # Dependencies & scripts
├── package-lock.json       # Locked dependencies (required for npm ci)
├── Dockerfile              # Container definition
├── Jenkinsfile             # Pipeline definition
├── setup-jenkins.sh        # Jenkins EC2 bootstrap (runs via Terraform user_data)
└── terraform/              # Infrastructure
```

---

## 3. Jenkins Server — First-Time Setup

Jenkins is provisioned automatically by Terraform via `setup-jenkins.sh` as EC2 `user_data`. **You do not need to run anything manually** — by the time the instance is reachable, the script has already:

- Installed Docker on the host
- Pulled `jenkins/jenkins:lts` and started it with `--restart unless-stopped`
- Mounted `/var/run/docker.sock` so pipeline stages can build and push images
- Set proper Docker socket permissions
- Installed the Docker CLI and Node.js 18 inside the container
- Exposed Jenkins on port `8080`

To verify everything came up correctly after `terraform apply`:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<JENKINS_IP>

# Container should show STATUS "Up X minutes"
sudo docker ps

# Review the setup log for any errors
sudo cat /var/log/jenkins-setup.log

# Verify Docker works inside Jenkins container
sudo docker exec jenkins docker ps
```

---

## 4. Configure the App Server

The app server only needs Docker. SSH in and run:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>
```

```bash
sudo yum install -y docker
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ec2-user
exit   # log out so the group change takes effect
```

---

## 5. Get the Initial Admin Password

Jenkins generates a one-time password on first boot. Because Jenkins runs inside a container, retrieve it with `docker exec` — **not** from the host filesystem:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<JENKINS_IP>

sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

> If the command returns "No such file or directory", Jenkins hasn't finished starting yet. Wait 30 seconds and try again, or check `sudo docker logs jenkins` to see where it is in the boot sequence.

---

## 6. Install Jenkins Plugins

1. Open **`http://<JENKINS_IP>:8080`** in your browser.
2. Paste the initial admin password from the step above.
3. Choose **"Install suggested plugins"** and wait for completion.
4. Create your admin user when prompted.

Then install the additional required plugins via **Manage Jenkins → Plugins → Available plugins**:

| Plugin | Purpose |
|--------|---------|
| `Pipeline` | Declarative pipeline support |
| `Git` | Checkout from GitHub |
| `Credentials Binding` | Inject secrets into the pipeline |
| `Docker Pipeline` | `docker` steps in the Jenkinsfile |
| `SSH Agent` | `sshagent` step for deployment |
| `NodeJS` | Manage Node.js versions in Jenkins |

Tick all checkboxes → **Install** → **"Restart Jenkins when no jobs are running"**.

### Configure the NodeJS tool

**Manage Jenkins → Tools → NodeJS → Add NodeJS**

| Field | Value |
|-------|-------|
| Name | `nodejs-18` |
| Version | `NodeJS 18.x` |
| Install automatically | ✅ Checked |

Click **Save**.

---

## 7. Add Jenkins Credentials

Navigate to: **Manage Jenkins → Credentials → System → Global credentials → Add Credential**

### `registry_creds` — Docker Hub

| Field | Value |
|-------|-------|
| Kind | `Username with password` |
| Username | Your Docker Hub username |
| Password | Your Docker Hub access token |
| ID | `registry_creds` |

> Generate a token at: hub.docker.com → Account Settings → Security → New Access Token

### `ec2_ssh` — App Server SSH Key

| Field | Value |
|-------|-------|
| Kind | `SSH Username with private key` |
| Username | `ec2-user` |
| Private Key | Enter directly → paste the full `.pem` file contents |
| ID | `ec2_ssh` |

Get the key content on your local machine:

```bash
cat jenkins-cicd-pipeline-dev-keypair.pem
```

Paste everything including the `-----BEGIN` and `-----END` lines.

---

## 8. Create the Pipeline Job

### Create the job in Jenkins

1. **Dashboard → New Item**
2. Name: `cicd-pipeline` → select **Pipeline** → **OK**

**General:**
- ✅ This project is parameterized
  - Add Parameter → String Parameter
  - Name: `EC2_HOST`
  - Description: `Public IP of the app server EC2 instance`
- ✅ Discard old builds → Max builds to keep: `5`

**Build Triggers (optional):**
- ✅ GitHub hook trigger for GITScm polling

**Pipeline:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/YOUR_USERNAME/YOUR_REPO.git`
- Branch: `*/main`
- Script Path: `Jenkinsfile`

Click **Save**.

---

## 9. Run the Pipeline

1. Click **"Build with Parameters"** on the job page.
2. Enter your app server IP (get it from `cat infrastructure-outputs.txt`)
3. Click **"Build"**
4. Click the build number in Build History.
5. Click **"Console Output"** to watch live.

### Expected stages

```
Checkout         ✅
Install/Build    ✅  (npm ci)
Test             ✅  (all tests passed)
Docker Build     ✅  (tagged :N and :latest)
Push Image       ✅  (pushed to Docker Hub)
Deploy           ✅  (container running on app server)
Post: cleanup    ✅
```

A successful run ends with:

```
Finished: SUCCESS
Pipeline completed successfully!
```

---

## 10. Verify Deployment

```bash
curl http://<APP_IP>:5000
curl http://<APP_IP>:5000/health
curl http://<APP_IP>:5000/api/info
```

Or open in browser: `http://<APP_IP>:5000`

Verify the container on the app server:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>

docker ps                    # confirms node-app is running
docker logs node-app -f      # live app logs
```

---

## 11. Updating the App Server IP

Every time EC2 instances are stopped and restarted, both IPs change. Checklist:

```
1. cat infrastructure-outputs.txt        (or: cd terraform && terraform output)
2. Note the new app_server_public_ip
3. In Jenkins, click "Build with Parameters"
4. Enter the new IP in the EC2_HOST field
5. Click "Build"
```

The Jenkins UI URL also changes — always derive it from the current `<JENKINS_IP>:8080`.

---

## 12. Troubleshooting

### Jenkins container is not running

```bash
# Check if it exists but is stopped
sudo docker ps -a

# Check startup logs
sudo docker logs jenkins

# Check the Terraform bootstrap log for errors
sudo cat /var/log/jenkins-setup.log

# Start it manually if needed
sudo docker start jenkins
```

### Jenkins UI not reachable

Confirm the container is up (`sudo docker ps`) and that the EC2 security group allows inbound TCP 8080 from your IP.

### Initial admin password file not found

Jenkins runs inside the container — the password is never on the host filesystem. Always use:

```bash
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### `docker: command not found` in pipeline

The Docker CLI is installed inside the container by `setup-jenkins.sh`. If it's missing, install it manually:

```bash
sudo docker exec -u root jenkins bash -c "apt-get update -qq && apt-get install -y docker.io"
```

### `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`

This means Jenkins cannot access the Docker socket. There are two possible causes:

**1. Docker socket not mounted in container**

Check if the socket exists inside the Jenkins container:

```bash
sudo docker exec jenkins ls -l /var/run/docker.sock
```

If you see "No such file or directory", the socket wasn't mounted. You need to recreate the container:

```bash
# Stop and remove current container
sudo docker stop jenkins
sudo docker rm jenkins

# Get Docker GID
DOCKER_GID=$(getent group docker | cut -d: -f3)

# Recreate with proper mounts
sudo docker run -d \
  -p 8080:8080 \
  -p 50000:50000 \
  --restart unless-stopped \
  --name jenkins \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --user root \
  --group-add ${DOCKER_GID} \
  jenkins/jenkins:lts

# Wait for startup
sleep 45

# Reinstall Docker CLI
sudo docker exec -u root jenkins bash -c "apt-get update -qq && apt-get install -y docker.io"

# Verify it works
sudo docker exec jenkins docker ps
```

**Note**: Your Jenkins configuration is preserved in the `jenkins_home` volume, so you won't lose your settings, credentials, or jobs.

**2. Docker socket permission issue**

If the socket exists but Jenkins can't access it, fix permissions:

```bash
# Fix socket permissions
sudo chmod 666 /var/run/docker.sock

# Verify Jenkins can now access Docker
sudo docker exec jenkins docker ps
```

To make this fix permanent across reboots:

```bash
# Create systemd service
sudo tee /etc/systemd/system/docker-socket-permissions.service > /dev/null <<'EOF'
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
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable docker-socket-permissions.service
sudo systemctl start docker-socket-permissions.service
```

### `npm: command not found` in pipeline

Confirm the **NodeJS plugin** is installed and the `nodejs-18` tool is configured under **Manage Jenkins → Tools**. The Jenkinsfile must reference it:

```groovy
tools { nodejs 'nodejs-18' }
```

### `npm ci` fails: "can only install with an existing package-lock.json"

You need to generate and commit `package-lock.json`:

```bash
# On your local machine
npm install

# This creates package-lock.json
git add package-lock.json
git commit -m "Add package-lock.json for npm ci"
git push
```

### SSH deploy fails: `Permission denied (publickey)`

- Confirm `ec2_ssh` credential contains the correct full `.pem` contents.
- Confirm the username is exactly `ec2-user`.
- Test manually from inside the Jenkins container:

```bash
sudo docker exec -it jenkins ssh -o StrictHostKeyChecking=no ec2-user@<APP_IP> "docker ps"
```

### Docker Hub push fails: `unauthorized`

- Confirm the credential ID is exactly `registry_creds`.
- Confirm your Docker Hub username is correct in the `REGISTRY_CREDS` credential.
- Check the access token hasn't expired.

### Tests fail in pipeline but pass locally

```bash
# Check Node version inside the container
sudo docker exec jenkins node --version

# Run tests manually in the workspace
sudo docker exec jenkins bash -c "cd /var/jenkins_home/workspace/cicd-pipeline && npm ci && npm test"
```

### `Jest did not exit one second after the test run has completed`

This warning means the Express server is still running after tests. Fix by preventing the server from starting during tests:

Update `app.js` to only start the server when run directly (not when imported by tests):

```javascript
// Only start server if this file is run directly (not imported for tests)
if (require.main === module) {
    const port = process.env.PORT || 5000;
    app.listen(port, '0.0.0.0', () => {
        console.log(`Server running on port ${port}`);
    });
}

module.exports = app;
```

This allows `supertest` to handle the server lifecycle during testing.

### Docker on app server not accessible

If deployment fails because Docker isn't running on the app server:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>

# Check Docker status
sudo systemctl status docker

# If not running, start it
sudo systemctl start docker
sudo systemctl enable docker

# Verify ec2-user can use Docker
docker ps

# If permission denied, add user to docker group
sudo usermod -aG docker ec2-user
exit  # log out and back in for group changes to take effect
```

### Container fails to start on app server

Check the logs on the app server:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>

# Check if container exists
docker ps -a

# View logs
docker logs node-app

# Common issues:
# - Port 5000 already in use
# - Image failed to pull
# - Application crash on startup
```
```

---

Save this as your complete runbook! 🚀