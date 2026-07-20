###############################################################################
# EKS platform example
#
# Builds a complete, production-shaped platform:
#   - a three-AZ VPC with public / private / intra tiers
#   - an EKS cluster with a private API endpoint and two managed node groups
#   - IRSA roles for the AWS Load Balancer Controller, external-dns and the
#     cluster autoscaler
#   - an S3 bucket for application artifacts, writable only by the app's IRSA role
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

locals {
  name = "${var.project}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
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

  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  intra_subnets   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  enable_nat_gateway = true
  # One NAT per AZ in production, a single shared one everywhere else.
  single_nat_gateway = var.environment != "prod"

  enable_flow_logs            = true
  flow_logs_retention_in_days = 90

  # Tags the AWS Load Balancer Controller uses for subnet auto-discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  tags = local.tags
}

################################################################################
# EKS
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Private-only API endpoint. Reach it through a bastion, VPN or SSM tunnel.
  endpoint_private_access = true
  endpoint_public_access  = false

  enable_irsa         = true
  authentication_mode = "API_AND_CONFIG_MAP"

  node_groups = {
    # General workloads, on-demand for predictable capacity.
    general = {
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 3
      min_size       = 3
      max_size       = 6
      disk_size      = 100
      labels         = { workload = "general" }
    }

    # Interruption-tolerant batch work on spot, tainted so only jobs that
    # tolerate it land here.
    spot = {
      instance_types = ["m6i.large", "m5.large", "m5a.large"]
      capacity_type  = "SPOT"
      desired_size   = 2
      min_size       = 0
      max_size       = 10
      labels         = { workload = "batch" }

      taints = [{
        key    = "workload"
        value  = "batch"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  tags = local.tags
}

################################################################################
# IRSA roles
################################################################################

module "ebs_csi_irsa" {
  source = "../../modules/iam-irsa-role"

  name                       = "${local.name}-ebs-csi"
  description                = "EBS CSI driver for ${local.name}"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]

  policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]

  tags = local.tags
}

module "load_balancer_controller_irsa" {
  source = "../../modules/iam-irsa-role"

  name                       = "${local.name}-aws-lbc"
  description                = "AWS Load Balancer Controller for ${local.name}"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]

  inline_policy = data.aws_iam_policy_document.load_balancer_controller.json

  tags = local.tags
}

module "cluster_autoscaler_irsa" {
  source = "../../modules/iam-irsa-role"

  name                       = "${local.name}-cluster-autoscaler"
  description                = "Cluster autoscaler for ${local.name}"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["kube-system:cluster-autoscaler"]

  inline_policy = data.aws_iam_policy_document.cluster_autoscaler.json

  tags = local.tags
}

module "app_irsa" {
  source = "../../modules/iam-irsa-role"

  name                       = "${local.name}-app"
  description                = "Application workload role for ${local.name}"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["${var.app_namespace}:${var.app_service_account}"]

  inline_policy = data.aws_iam_policy_document.app.json

  tags = local.tags
}

################################################################################
# Application artifact bucket
################################################################################

module "artifacts_bucket" {
  source = "../../modules/s3-bucket"

  bucket_prefix = "${local.name}-artifacts-"

  versioning_enabled = true
  create_kms_key     = true
  enforce_tls        = true

  # Non-prod buckets are disposable so the example can be torn down cleanly.
  force_destroy = var.environment != "prod"

  lifecycle_rules = [
    {
      id     = "expire-old-versions"
      prefix = ""

      noncurrent_version_transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
      ]

      noncurrent_version_expiration_days     = 180
      abort_incomplete_multipart_upload_days = 7
    },
    {
      id     = "archive-build-logs"
      prefix = "logs/"

      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]

      expiration_days = 365
    },
  ]

  tags = local.tags
}

################################################################################
# IAM policy documents
################################################################################

data "aws_iam_policy_document" "app" {
  statement {
    sid    = "ReadWriteArtifacts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    resources = [
      module.artifacts_bucket.bucket_arn,
      "${module.artifacts_bucket.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "UseBucketKmsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [module.artifacts_bucket.kms_key_arn]
  }
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "DescribeAutoscaling"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ModifyOwnedAutoscalingGroups"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]

    resources = ["*"]

    # Scoped to ASGs this cluster owns, so the autoscaler cannot touch
    # capacity belonging to anything else in the account.
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${local.name}"
      values   = ["owned"]
    }
  }
}

data "aws_iam_policy_document" "load_balancer_controller" {
  statement {
    sid    = "DescribeNetworking"
    effect = "Allow"

    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:Describe*",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ManageLoadBalancers"
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [local.name]
    }
  }

  statement {
    sid    = "CreateServiceLinkedRole"
    effect = "Allow"

    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}
