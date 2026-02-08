output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "jenkins_public_ip" {
  description = "Public IP address of Jenkins server"
  value       = module.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${module.jenkins.public_ip}:8080"
}

output "app_server_public_ip" {
  description = "Public IP address of application server"
  value       = module.app_server.public_ip
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.app_server.public_ip}:5000"
}

output "ssh_jenkins" {
  description = "SSH command for Jenkins server"
  value       = "ssh -i ${module.keypair.private_key_filename} ec2-user@${module.jenkins.public_ip}"
}

output "ssh_app_server" {
  description = "SSH command for application server"
  value       = "ssh -i ${module.keypair.private_key_filename} ec2-user@${module.app_server.public_ip}"
}