output "bucket_id" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket. Prefer this over the global name to avoid cross-region redirects."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region the bucket resides in."
  value       = aws_s3_bucket.this.region
}

output "kms_key_arn" {
  description = "ARN of the KMS key protecting the bucket, or null when using SSE-S3."
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key created by this module, or null when no key was created."
  value       = try(aws_kms_key.this[0].key_id, null)
}
