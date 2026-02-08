resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.environment}-keypair"
  public_key = tls_private_key.main.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-keypair"
  }
}

resource "local_file" "private_key" {
  content  = tls_private_key.main.private_key_pem
  filename = "${var.project_name}-${var.environment}-keypair.pem"
  file_permission = "0600"
}

resource "local_file" "public_key" {
  content  = tls_private_key.main.public_key_openssh
  filename = "${var.project_name}-${var.environment}-keypair.pub"
  file_permission = "0644"
}