variable "identifier" {
  description = "Identifier for the RDS instance. Also used as a name prefix for supporting resources."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version. Use a major version alone (e.g. \"16\") to track the latest minor release."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 50

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Upper bound in GiB for storage autoscaling. Set to 0 to disable autoscaling."
  type        = number
  default     = 500
}

variable "storage_type" {
  description = "Storage type. gp3 is the sensible default; io1/io2 only when you have a measured IOPS requirement."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be gp2, gp3, io1 or io2."
  }
}

variable "iops" {
  description = "Provisioned IOPS. Only valid for io1/io2, or gp3 above 400 GiB."
  type        = number
  default     = null
}

variable "storage_throughput" {
  description = "Storage throughput in MiB/s. gp3 only."
  type        = number
  default     = null
}

variable "db_name" {
  description = "Name of the database created on the instance."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a letter and contain only letters, digits and underscores."
  }
}

variable "username" {
  description = "Master username. Note that `admin`, `rdsadmin` and `postgres` are reserved by RDS in some configurations."
  type        = string
  default     = "dbadmin"
}

variable "port" {
  description = "TCP port the database listens on."
  type        = number
  default     = 5432
}

variable "vpc_id" {
  description = "ID of the VPC hosting the instance."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Use private or intra subnets across at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security group IDs permitted to connect on the database port. This is the preferred way to grant access."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks permitted to connect on the database port. Prefer `allowed_security_group_ids` where possible."
  type        = list(string)
  default     = []
}

variable "multi_az" {
  description = "Deploy a synchronous standby in a second AZ. Roughly doubles cost; required for most production workloads."
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Assign a public IP to the instance. Leave false."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block accidental deletion of the instance."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Only sensible for ephemeral environments."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to retain. 0 disables backups entirely."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Daily backup window in UTC, `hh:mm-hh:mm`."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC, `ddd:hh:mm-ddd:hh:mm`. Must not overlap the backup window."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "copy_tags_to_snapshot" {
  description = "Copy instance tags onto snapshots."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of waiting for the maintenance window."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor engine upgrades during the maintenance window."
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "Permit major version upgrades. Requires a compatible parameter group family."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption. Defaults to the AWS-managed RDS key when null."
  type        = string
  default     = null
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days. 7 is free tier; other valid values are 731 or a multiple of 31."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds. 0 disables it; valid values are 0, 1, 5, 10, 15, 30 and 60."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types exported to CloudWatch Logs."
  type        = list(string)
  default     = ["postgresql", "upgrade"]
}

variable "parameter_group_family" {
  description = "Parameter group family, e.g. `postgres16`. Must match the major version in `engine_version`."
  type        = string
  default     = "postgres16"
}

variable "parameters" {
  description = "Parameters applied to the generated DB parameter group. `apply_method` is `immediate` or `pending-reboot`."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = [
    {
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    },
    {
      name         = "log_connections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_disconnections"
      value        = "1"
      apply_method = "immediate"
    },
  ]
}

variable "manage_master_user_password" {
  description = <<-EOT
    Let RDS generate and rotate the master password in Secrets Manager (the managed integration).
    When false the module generates a random password itself and stores it in a Secrets Manager
    secret it owns. The managed integration is preferred - the password never passes through
    Terraform state.
  EOT
  type        = bool
  default     = true
}

variable "master_user_secret_kms_key_arn" {
  description = "KMS key ARN protecting the master user secret. Defaults to the AWS-managed key when null."
  type        = string
  default     = null
}

variable "password_rotation_days" {
  description = "Rotation interval in days for the self-managed secret. Only used when `manage_master_user_password` is false."
  type        = number
  default     = 30
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window for the self-managed secret. 0 deletes it immediately."
  type        = number
  default     = 7
}

variable "create_cloudwatch_alarms" {
  description = "Create baseline CloudWatch alarms for CPU, free storage and connection count."
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "ARNs notified when an alarm fires, e.g. an SNS topic."
  type        = list(string)
  default     = []
}

variable "cpu_utilization_alarm_threshold" {
  description = "CPU utilization percentage that triggers the CPU alarm."
  type        = number
  default     = 80
}

variable "free_storage_alarm_threshold_bytes" {
  description = "Free storage in bytes below which the storage alarm fires. Defaults to 10 GiB."
  type        = number
  default     = 10737418240
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
