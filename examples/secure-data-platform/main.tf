###############################################################################
# Secure data platform example
#
# A data-tier stack that deliberately keeps the database off the internet:
#   - VPC with private (compute) and intra (data) tiers; the DB lives in intra
#     subnets that have no route to a NAT gateway at all
#   - Multi-AZ PostgreSQL with the RDS-managed Secrets Manager password
#   - A KMS-encrypted data lake bucket with tiered lifecycle rules
#   - An audit log bucket with a long, immutable-ish retention policy
#   - An IRSA role letting an EKS workload read the DB secret and use the lake
#
# The EKS cluster itself is an input here rather than something this example
# creates, which is the realistic shape: the data platform is layered onto a
# cluster that already exists.
###############################################################################

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    DataClass   = "confidential"
  }
}

################################################################################
# Network
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  name       = local.name
  cidr_block = var.vpc_cidr
  azs        = local.azs

  public_subnets  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  # Data tier. No internet route in or out, by construction rather than by
  # security group rules alone.
  intra_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"

  enable_flow_logs            = true
  flow_logs_traffic_type      = "ALL"
  flow_logs_retention_in_days = 365

  intra_subnet_tags = { Tier = "data" }

  tags = local.tags
}

################################################################################
# Compute security group
#
# Stands in for whatever runs the workload (EKS nodes, ECS tasks, a bastion).
# RDS trusts this security group rather than a CIDR range.
################################################################################

resource "aws_security_group" "compute" {
  name_prefix = "${local.name}-compute-"
  description = "Application compute tier for ${local.name}"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Name = "${local.name}-compute" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "compute_all" {
  security_group_id = aws_security_group.compute.id
  description       = "Compute egress to everywhere"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = local.tags
}

################################################################################
# PostgreSQL
################################################################################

module "postgres" {
  source = "../../modules/rds-postgres"

  identifier     = "${local.name}-pg"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnet_ids

  # Only the compute tier may open a connection.
  allowed_security_group_ids = concat(
    [aws_security_group.compute.id],
    var.additional_db_client_security_group_ids,
  )

  db_name  = var.db_name
  username = var.db_username

  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type          = "gp3"

  multi_az                = var.environment == "prod"
  deletion_protection     = var.environment == "prod"
  skip_final_snapshot     = var.environment != "prod"
  backup_retention_period = var.environment == "prod" ? 35 : 7

  # RDS owns and rotates the master password; it never lands in Terraform state.
  manage_master_user_password = true

  performance_insights_enabled = true
  monitoring_interval          = 60

  parameter_group_family = var.parameter_group_family

  parameters = [
    { name = "log_min_duration_statement", value = "500" },
    { name = "log_connections", value = "1" },
    { name = "log_disconnections", value = "1" },
    { name = "log_lock_waits", value = "1" },
    { name = "log_temp_files", value = "0" },
    # pg_stat_statements needs a reboot to load into shared_preload_libraries.
    { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
  ]

  create_cloudwatch_alarms = true
  alarm_actions            = var.alarm_sns_topic_arns

  tags = local.tags
}

################################################################################
# Data lake bucket
################################################################################

module "data_lake" {
  source = "../../modules/s3-bucket"

  bucket_prefix = "${local.name}-lake-"

  versioning_enabled = true
  create_kms_key     = true
  enforce_tls        = true
  force_destroy      = var.environment != "prod"

  logging = {
    target_bucket = module.audit_logs.bucket_id
    target_prefix = "s3-access/data-lake/"
  }

  lifecycle_rules = [
    {
      id     = "tier-raw-zone"
      prefix = "raw/"

      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER_IR" },
        { days = 365, storage_class = "DEEP_ARCHIVE" },
      ]

      noncurrent_version_expiration_days     = 90
      abort_incomplete_multipart_upload_days = 7
    },
    {
      id     = "tier-curated-zone"
      prefix = "curated/"

      transitions = [
        { days = 60, storage_class = "STANDARD_IA" },
      ]

      noncurrent_version_expiration_days = 180
    },
    {
      id              = "expire-scratch"
      prefix          = "scratch/"
      expiration_days = 14
    },
  ]

  tags = merge(local.tags, { Purpose = "data-lake" })
}

################################################################################
# Audit log bucket
################################################################################

module "audit_logs" {
  source = "../../modules/s3-bucket"

  bucket_prefix = "${local.name}-audit-"

  versioning_enabled = true
  enforce_tls        = true

  # Audit logs are never force-destroyed, even outside production.
  force_destroy = false

  # SSE-S3 rather than SSE-KMS: the S3 log delivery service cannot write to a
  # bucket encrypted with a customer-managed KMS key.
  create_kms_key = false

  policy_statements = [
    {
      Sid       = "AllowS3LogDelivery"
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::${local.name}-audit-*/*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }
  ]

  lifecycle_rules = [
    {
      id     = "retain-audit-logs"
      prefix = ""

      transitions = [
        { days = 90, storage_class = "GLACIER" },
      ]

      expiration_days                        = 2555 # ~7 years
      abort_incomplete_multipart_upload_days = 7
    },
  ]

  tags = merge(local.tags, { Purpose = "audit-logs" })
}

################################################################################
# IRSA role for the data workload
################################################################################

module "data_workload_irsa" {
  source = "../../modules/iam-irsa-role"

  name                       = "${local.name}-data-workload"
  description                = "Data pipeline workload for ${local.name}"
  oidc_provider_arn          = var.oidc_provider_arn
  namespace_service_accounts = ["${var.data_namespace}:${var.data_service_account}"]

  inline_policy = data.aws_iam_policy_document.data_workload.json

  tags = local.tags
}

data "aws_iam_policy_document" "data_workload" {
  statement {
    sid    = "ReadWriteDataLake"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      module.data_lake.bucket_arn,
      "${module.data_lake.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "UseDataLakeKmsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = [module.data_lake.kms_key_arn]
  }

  statement {
    sid    = "ReadDatabaseCredentials"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [module.postgres.master_user_secret_arn]
  }
}
