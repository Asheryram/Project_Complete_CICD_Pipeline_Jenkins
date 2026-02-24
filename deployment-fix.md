# Jenkins Deployment Fix

## Issue
SSH connection timeout when Jenkins tries to deploy to app server at `10.0.2.145`

## Solution Steps

### 1. Verify Jenkins Job Configuration
When running the Jenkins pipeline, ensure the `EC2_HOST` parameter is set to:
```
10.0.2.145
```

### 2. Check SSH Key Configuration
Verify Jenkins has the correct SSH credentials configured:
- Credential ID: `ec2_ssh`
- Should contain the private key from AWS Secrets Manager

### 3. Test SSH Connection Manually
SSH from Jenkins server to app server to verify connectivity:
```bash
# From Jenkins server (18.197.66.70)
ssh -i /path/to/key ec2-user@10.0.2.145
```

### 4. Alternative: Use Public IP for Deployment
Modify Jenkinsfile to use public IP instead of private IP:
```groovy
// Change from private IP to public IP
EC2_HOST: '3.75.93.68'  // App server public IP
```

### 5. Verify Security Group Rules
Ensure Jenkins security group allows outbound SSH to app server:
- Source: Jenkins SG (sg-04e8927e54912ffed)
- Destination: App SG (sg-0d90bb7de58daa20a)
- Port: 22

## Current Infrastructure IPs
- Jenkins Server: 18.197.66.70 (public), 10.0.1.179 (private)
- App Server: 3.75.93.68 (public), 10.0.2.145 (private)
- Monitoring Server: 18.153.91.237 (public), 10.0.1.249 (private)

## Recommended Fix
Use the public IP for deployment to avoid VPC routing issues:
```bash
# In Jenkins job parameters
EC2_HOST: 3.75.93.68
```