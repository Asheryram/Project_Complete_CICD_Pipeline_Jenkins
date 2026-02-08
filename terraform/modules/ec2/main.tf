resource "aws_instance" "app_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  user_data              = var.user_data

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-server"
    Project     = var.project_name
    Environment = var.environment
  }
}