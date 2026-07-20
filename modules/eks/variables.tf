variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes minor version for the control plane, e.g. \"1.31\"."
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.cluster_version))
    error_message = "cluster_version must be a Kubernetes minor version such as 1.31."
  }
}

variable "vpc_id" {
  description = "ID of the VPC hosting the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the worker nodes. These should normally be private subnets across at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "control_plane_subnet_ids" {
  description = "Subnet IDs for the control plane ENIs. Defaults to `subnet_ids` when empty."
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint to the internet."
  type        = bool
  default     = false
}

variable "endpoint_private_access" {
  description = "Expose the Kubernetes API endpoint inside the VPC."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks permitted to reach the public API endpoint. Ignored when `endpoint_public_access` is false."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "Valid log types are api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "cluster_log_retention_in_days" {
  description = "Retention for the control plane CloudWatch Logs group."
  type        = number
  default     = 90
}

variable "cluster_encryption_kms_key_arn" {
  description = "KMS key ARN used for envelope encryption of Kubernetes secrets. When null a dedicated key is created if `create_kms_key` is true."
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Create a dedicated, rotating KMS key for envelope encryption of Kubernetes secrets."
  type        = bool
  default     = true
}

variable "authentication_mode" {
  description = "Cluster access management mode: API, API_AND_CONFIG_MAP or CONFIG_MAP. API is the modern default and enables EKS access entries."
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API, API_AND_CONFIG_MAP or CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Grant the IAM principal running Terraform cluster-admin via an access entry."
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Create the IAM OIDC identity provider so service accounts can assume IAM roles."
  type        = bool
  default     = true
}

variable "cluster_security_group_additional_rules" {
  description = <<-EOT
    Extra ingress rules on the cluster security group. Map key is an arbitrary rule name; each value supports:
      description, from_port, to_port, protocol, cidr_blocks, source_security_group_id
  EOT
  type = map(object({
    description              = optional(string, "Managed by Terraform")
    from_port                = number
    to_port                  = number
    protocol                 = optional(string, "tcp")
    cidr_blocks              = optional(list(string))
    source_security_group_id = optional(string)
  }))
  default = {}
}

variable "node_security_group_additional_rules" {
  description = "Extra ingress rules on the shared node security group. Same shape as `cluster_security_group_additional_rules`."
  type = map(object({
    description              = optional(string, "Managed by Terraform")
    from_port                = number
    to_port                  = number
    protocol                 = optional(string, "tcp")
    cidr_blocks              = optional(list(string))
    source_security_group_id = optional(string)
  }))
  default = {}
}

variable "node_groups" {
  description = <<-EOT
    Managed node groups, keyed by name. Each group supports:
      instance_types  - EC2 instance types (default ["t3.large"])
      capacity_type   - ON_DEMAND or SPOT (default ON_DEMAND)
      ami_type        - AL2023_x86_64_STANDARD, BOTTLEROCKET_x86_64, ... (default AL2023_x86_64_STANDARD)
      desired_size / min_size / max_size - autoscaling bounds
      disk_size       - root volume size in GiB
      subnet_ids      - override the cluster-level subnets for this group
      labels / taints - Kubernetes labels and taints
      max_unavailable_percentage - rolling update budget
      additional_policy_arns     - extra IAM policies for the node role
  EOT
  type = map(object({
    instance_types             = optional(list(string), ["t3.large"])
    capacity_type              = optional(string, "ON_DEMAND")
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    desired_size               = optional(number, 2)
    min_size                   = optional(number, 1)
    max_size                   = optional(number, 4)
    disk_size                  = optional(number, 50)
    subnet_ids                 = optional(list(string))
    labels                     = optional(map(string), {})
    max_unavailable_percentage = optional(number, 33)
    additional_policy_arns     = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default = {
    default = {}
  }

  validation {
    condition     = alltrue([for g in var.node_groups : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for g in var.node_groups : g.min_size <= g.desired_size && g.desired_size <= g.max_size])
    error_message = "Each node group must satisfy min_size <= desired_size <= max_size."
  }
}

variable "cluster_addons" {
  description = <<-EOT
    EKS managed addons, keyed by addon name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, ...).
    Each entry supports `addon_version`, `service_account_role_arn`, `configuration_values`,
    `resolve_conflicts_on_create` and `resolve_conflicts_on_update`. Leave `addon_version` null
    to let EKS pick the default version for the cluster's Kubernetes release.
  EOT
  type = map(object({
    addon_version               = optional(string)
    service_account_role_arn    = optional(string)
    configuration_values        = optional(string)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    preserve                    = optional(bool, true)
  }))
  default = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
