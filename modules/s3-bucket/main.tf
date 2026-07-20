locals {
  tags = merge(var.tags, { "terraform-module" = "s3-bucket" })

  create_kms_key = var.create_kms_key && var.kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  sse_algorithm  = local.kms_key_arn != null ? "aws:kms" : "AES256"

  tls_statements = var.enforce_tls ? [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }
  ] : []

  policy_statements = concat(local.tls_statements, var.policy_statements)
  create_policy     = length(local.policy_statements) > 0
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy

  tags = local.tags

  lifecycle {
    precondition {
      condition     = (var.bucket == null) != (var.bucket_prefix == null)
      error_message = "Exactly one of `bucket` or `bucket_prefix` must be set."
    }
  }
}

################################################################################
# Encryption
################################################################################

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "SSE-KMS key for S3 bucket ${coalesce(var.bucket, var.bucket_prefix)}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name_prefix   = "alias/s3/${coalesce(var.bucket, var.bucket_prefix)}-"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.kms_key_arn
    }

    # Only meaningful for SSE-KMS; S3 ignores it for AES256.
    bucket_key_enabled = local.sse_algorithm == "aws:kms" ? var.bucket_key_enabled : null
  }
}

################################################################################
# Versioning
################################################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status     = var.versioning_enabled ? "Enabled" : "Suspended"
    mfa_delete = var.mfa_delete ? "Enabled" : "Disabled"
  }
}

################################################################################
# Public access / ownership
################################################################################

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.block_public_access ? 1 : 0

  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

################################################################################
# Bucket policy
################################################################################

resource "aws_s3_bucket_policy" "this" {
  count = local.create_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })

  # A public access block that blocks public policies must exist before the
  # policy is evaluated, otherwise S3 can briefly reject the policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

################################################################################
# Lifecycle
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        and {
          prefix = rule.value.prefix
          tags   = rule.value.tags
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions

        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []

        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [rule.value.noncurrent_version_expiration_days] : []

        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [rule.value.abort_incomplete_multipart_upload_days] : []

        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }

  # Lifecycle rules that act on noncurrent versions require versioning first.
  depends_on = [aws_s3_bucket_versioning.this]
}

################################################################################
# Access logging
################################################################################

resource "aws_s3_bucket_logging" "this" {
  count = var.logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging.target_bucket
  target_prefix = var.logging.target_prefix
}
