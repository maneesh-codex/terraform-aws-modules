output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs hosting the database tier."
  value       = module.vpc.intra_subnet_ids
}

output "compute_security_group_id" {
  description = "Security group ID for the application compute tier. Attach workloads here to reach PostgreSQL."
  value       = aws_security_group.compute.id
}

output "db_endpoint" {
  description = "PostgreSQL connection endpoint."
  value       = module.postgres.db_instance_endpoint
}

output "db_name" {
  description = "Name of the initial database."
  value       = module.postgres.db_instance_name
}

output "db_security_group_id" {
  description = "Security group ID in front of the database."
  value       = module.postgres.security_group_id
}

output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials, managed and rotated by RDS."
  value       = module.postgres.master_user_secret_arn
}

output "data_lake_bucket_id" {
  description = "Name of the data lake bucket."
  value       = module.data_lake.bucket_id
}

output "data_lake_kms_key_arn" {
  description = "ARN of the KMS key protecting the data lake."
  value       = module.data_lake.kms_key_arn
}

output "audit_logs_bucket_id" {
  description = "Name of the audit log bucket."
  value       = module.audit_logs.bucket_id
}

output "data_workload_role_arn" {
  description = "IRSA role ARN for the data workload. Annotate the service account with this."
  value       = module.data_workload_irsa.iam_role_arn
}

output "data_workload_service_account_annotation" {
  description = "Ready-to-paste service account annotation for the data workload."
  value       = module.data_workload_irsa.service_account_annotation
}
