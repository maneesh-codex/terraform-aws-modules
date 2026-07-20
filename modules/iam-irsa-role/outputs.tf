output "iam_role_arn" {
  description = "ARN of the IAM role. Annotate the service account with `eks.amazonaws.com/role-arn: <this value>`."
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.this.name
}

output "iam_role_unique_id" {
  description = "Stable unique ID of the IAM role."
  value       = aws_iam_role.this.unique_id
}

output "service_account_annotation" {
  description = "Ready-to-use annotation map for the Kubernetes service account manifest."
  value       = { "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn }
}

output "oidc_issuer" {
  description = "OIDC issuer host/path derived from the provider ARN, as used in the trust policy conditions."
  value       = local.oidc_issuer
}
