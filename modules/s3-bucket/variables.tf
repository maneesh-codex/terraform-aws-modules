variable "bucket" {
  description = "Name of the S3 bucket. Must be globally unique. Mutually exclusive with `bucket_prefix`."
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "Creates a bucket with a unique name beginning with this prefix. Mutually exclusive with `bucket`."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket even when it still holds objects. Leave false outside of throwaway environments."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable object versioning. Strongly recommended - it is the safety net behind lifecycle rules and accidental deletes."
  type        = bool
  default     = true
}

variable "mfa_delete" {
  description = "Require MFA to permanently delete an object version. Can only be toggled by the bucket owner using root credentials."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for SSE-KMS. When null the module falls back to SSE-S3 (AES256) unless `create_kms_key` is true."
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Create a dedicated, rotating KMS key for this bucket. Ignored when `kms_key_arn` is supplied."
  type        = bool
  default     = false
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period before a scheduled KMS key deletion completes."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}

variable "bucket_key_enabled" {
  description = "Use an S3 bucket key to cut KMS request costs on SSE-KMS buckets."
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Apply the full S3 public access block (all four settings). Disable only with a very good reason, such as a static website bucket."
  type        = bool
  default     = true
}

variable "object_ownership" {
  description = "Object ownership setting. BucketOwnerEnforced disables ACLs entirely and is the recommended modern default."
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be BucketOwnerEnforced, BucketOwnerPreferred or ObjectWriter."
  }
}

variable "enforce_tls" {
  description = "Attach a bucket policy statement denying any request that does not arrive over TLS."
  type        = bool
  default     = true
}

variable "policy_statements" {
  description = "Extra IAM policy statements (as JSON-encodable objects) merged into the bucket policy alongside the TLS statement."
  type        = list(any)
  default     = []
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules for the bucket. Each rule supports:
      id                                     - unique rule identifier (required)
      enabled                                - whether the rule is active (default true)
      prefix                                 - object key prefix the rule applies to (default "", meaning all objects)
      tags                                   - object tags the rule filters on
      transitions                            - list of { days, storage_class } for current versions
      noncurrent_version_transitions         - list of { days, storage_class } for previous versions
      expiration_days                        - delete current versions after N days
      noncurrent_version_expiration_days     - delete previous versions N days after they stop being current
      abort_incomplete_multipart_upload_days - clean up abandoned multipart uploads after N days
  EOT
  type = list(object({
    id                                     = string
    enabled                                = optional(bool, true)
    prefix                                 = optional(string, "")
    tags                                   = optional(map(string), {})
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    abort_incomplete_multipart_upload_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []
}

variable "logging" {
  description = "Server access logging target. Set to null to disable."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "")
  })
  default = null
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
