variable "name" {
  description = "Name prefix applied to the VPC and all subordinate resources."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Availability Zones to spread subnets across. Provide at least two for a highly available deployment."
  type        = list(string)

  validation {
    condition     = length(var.azs) > 0
    error_message = "At least one availability zone must be supplied."
  }
}

variable "public_subnets" {
  description = "CIDR blocks for the public subnets. Index order must line up with `azs`. Leave empty to skip public subnets (and the internet gateway)."
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "CIDR blocks for the private (egress via NAT) subnets. Index order must line up with `azs`."
  type        = list(string)
  default     = []
}

variable "intra_subnets" {
  description = "CIDR blocks for intra subnets. Intra subnets have no route to the internet at all and are intended for databases and internal endpoints."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Provision NAT gateways so private subnets get outbound internet access. Requires at least one public subnet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Deploy a single shared NAT gateway instead of one per AZ. Cheaper, but the NAT becomes a single point of failure and a cross-AZ data transfer cost."
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC. Required by EKS and RDS private endpoints."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC."
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Automatically assign a public IP to instances launched in public subnets."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs delivered to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Which traffic to capture in flow logs: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of ACCEPT, REJECT or ALL."
  }
}

variable "flow_logs_retention_in_days" {
  description = "Retention period for the flow log CloudWatch Logs group."
  type        = number
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_in_days)
    error_message = "flow_logs_retention_in_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "flow_logs_kms_key_arn" {
  description = "KMS key ARN used to encrypt the flow log group. Defaults to AWS-managed CloudWatch Logs encryption when null."
  type        = string
  default     = null
}

variable "public_subnet_tags" {
  description = "Additional tags applied only to public subnets. Commonly used for `kubernetes.io/role/elb`."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags applied only to private subnets. Commonly used for `kubernetes.io/role/internal-elb`."
  type        = map(string)
  default     = {}
}

variable "intra_subnet_tags" {
  description = "Additional tags applied only to intra subnets."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
