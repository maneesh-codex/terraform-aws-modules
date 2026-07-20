variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix for all resource names."
  type        = string
  default     = "dataplat"
}

variable "environment" {
  description = "Environment name. `prod` turns on Multi-AZ, deletion protection and longer backup retention."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owning team or individual, applied as the Owner tag."
  type        = string
  default     = "data-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a /16 for the subnet math in this example to work."
  type        = string
  default     = "10.30.0.0/16"
}

variable "postgres_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "parameter_group_family" {
  description = "DB parameter group family. Must match the major version in `postgres_version`."
  type        = string
  default     = "postgres16"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.large"
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "analytics"
}

variable "db_username" {
  description = "Master username for the database."
  type        = string
  default     = "dbadmin"
}

variable "additional_db_client_security_group_ids" {
  description = "Extra security groups allowed to reach PostgreSQL, e.g. an existing EKS node security group."
  type        = list(string)
  default     = []
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider of an existing EKS cluster. Use the `oidc_provider_arn` output of the eks module."
  type        = string
}

variable "data_namespace" {
  description = "Kubernetes namespace the data workload runs in."
  type        = string
  default     = "data"
}

variable "data_service_account" {
  description = "Name of the data workload's Kubernetes service account."
  type        = string
  default     = "pipeline"
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs notified when a database alarm fires."
  type        = list(string)
  default     = []
}
