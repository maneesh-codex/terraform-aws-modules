variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix for all resource names."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name. Anything other than `prod` gets cost-saving defaults (single NAT gateway, destroyable buckets)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owning team or individual, applied as the Owner tag."
  type        = string
  default     = "platform-engineering"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a /16 for the subnet math in this example to work."
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "app_namespace" {
  description = "Kubernetes namespace the application service account lives in."
  type        = string
  default     = "applications"
}

variable "app_service_account" {
  description = "Name of the application's Kubernetes service account."
  type        = string
  default     = "app"
}
