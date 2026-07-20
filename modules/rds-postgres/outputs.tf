output "db_instance_id" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_instance_endpoint" {
  description = "Connection endpoint in `host:port` form."
  value       = aws_db_instance.this.endpoint
}

output "db_instance_address" {
  description = "Hostname of the RDS instance."
  value       = aws_db_instance.this.address
}

output "db_instance_port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_instance_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "db_instance_username" {
  description = "Master username."
  value       = aws_db_instance.this.username
  sensitive   = true
}

output "db_instance_availability_zone" {
  description = "AZ hosting the primary instance."
  value       = aws_db_instance.this.availability_zone
}

output "db_instance_multi_az" {
  description = "Whether the instance is deployed Multi-AZ."
  value       = aws_db_instance.this.multi_az
}

output "db_instance_resource_id" {
  description = "Region-unique resource ID. Use this in IAM database authentication policies."
  value       = aws_db_instance.this.resource_id
}

output "security_group_id" {
  description = "ID of the security group in front of the instance."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Name of the DB parameter group."
  value       = aws_db_parameter_group.this.name
}

output "master_user_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding the master credentials, whichever path created it.
    With the RDS-managed integration this is the secret RDS owns and rotates.
  EOT
  value = try(
    aws_db_instance.this.master_user_secret[0].secret_arn,
    aws_secretsmanager_secret.master[0].arn,
    null,
  )
}

output "monitoring_role_arn" {
  description = "ARN of the enhanced monitoring IAM role, or null when monitoring is disabled."
  value       = try(aws_iam_role.monitoring[0].arn, null)
}

output "cloudwatch_alarm_arns" {
  description = "ARNs of the baseline CloudWatch alarms, when enabled."
  value = compact([
    try(aws_cloudwatch_metric_alarm.cpu[0].arn, ""),
    try(aws_cloudwatch_metric_alarm.free_storage[0].arn, ""),
    try(aws_cloudwatch_metric_alarm.connections[0].arn, ""),
  ])
}
