variable "name" {
  description = "Name of the IAM role. Used as a prefix when `use_name_prefix` is true."
  type        = string
}

variable "use_name_prefix" {
  description = "Treat `name` as a prefix and let AWS append a unique suffix. Helps avoid name collisions on role replacement."
  type        = bool
  default     = true
}

variable "description" {
  description = "Description attached to the IAM role."
  type        = string
  default     = "IAM role for a Kubernetes service account (IRSA)"
}

variable "path" {
  description = "IAM path for the role."
  type        = string
  default     = "/"
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, e.g. the `oidc_provider_arn` output of the eks module."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}

variable "namespace_service_accounts" {
  description = <<-EOT
    Kubernetes service accounts allowed to assume this role, in `namespace:serviceaccount` form.
    Both halves support `*` as a wildcard, e.g. `observability:*`. Wildcards force the trust policy
    to use StringLike instead of StringEquals, so keep them as narrow as you can.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.namespace_service_accounts) > 0
    error_message = "At least one namespace:serviceaccount pair must be supplied."
  }

  validation {
    condition     = alltrue([for sa in var.namespace_service_accounts : can(regex("^[^:]+:[^:]+$", sa))])
    error_message = "Each entry must be in `namespace:serviceaccount` form."
  }
}

variable "policy_arns" {
  description = "ARNs of existing managed policies to attach to the role."
  type        = list(string)
  default     = []
}

variable "inline_policy" {
  description = "Inline policy document (JSON) attached to the role. Use `data.aws_iam_policy_document` to build it."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "ARN of a policy used as the permissions boundary for the role."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the role."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "force_detach_policies" {
  description = "Force detaching any attached policies before destroying the role."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
