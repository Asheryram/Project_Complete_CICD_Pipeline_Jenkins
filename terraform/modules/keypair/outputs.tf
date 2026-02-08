output "key_name" {
  description = "Name of the created key pair"
  value       = aws_key_pair.main.key_name
}

output "private_key_filename" {
  description = "Filename of the private key file"
  value       = local_file.private_key.filename
}

output "private_key_pem" {
  description = "Private key in PEM format"
  value       = tls_private_key.main.private_key_pem
  sensitive   = true
}

output "public_key_openssh" {
  description = "Public key in OpenSSH format"
  value       = tls_private_key.main.public_key_openssh
}