output "cloudwatch_log_group_jenkins" {
  description = "CloudWatch log group for Jenkins"
  value       = aws_cloudwatch_log_group.jenkins.name
}

output "cloudwatch_log_group_app" {
  description = "CloudWatch log group for app server"
  value       = aws_cloudwatch_log_group.app.name
}

output "cloudwatch_log_group_monitoring" {
  description = "CloudWatch log group for monitoring server"
  value       = aws_cloudwatch_log_group.monitoring.name
}

output "cloudwatch_instance_profile_arn" {
  description = "IAM instance profile name for CloudWatch logs"
  value       = aws_iam_instance_profile.cloudwatch_logs.name
}

output "cloudtrail_bucket" {
  description = "S3 bucket for CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}