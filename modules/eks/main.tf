data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, { "terraform-module" = "eks" })

  control_plane_subnet_ids = length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.subnet_ids

  create_kms_key = var.create_kms_key && var.cluster_encryption_kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? aws_kms_key.this[0].arn : var.cluster_encryption_kms_key_arn

  partition = data.aws_partition.current.partition

  # Policies every managed node group needs to join the cluster and pull images.
  node_base_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  # Flatten {group => [policy...]} into a set of "group/policy" keys so each
  # attachment gets a stable, addressable identity.
  node_policy_attachments = merge([
    for group_name, group in var.node_groups : {
      for arn in distinct(concat(local.node_base_policy_arns, group.additional_policy_arns)) :
      "${group_name}/${arn}" => { group = group_name, policy_arn = arn }
    }
  ]...)
}

################################################################################
# KMS - envelope encryption for Kubernetes secrets
################################################################################

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "EKS secret envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.tags, { Name = "${var.cluster_name}-eks-secrets" })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/eks/${var.cluster_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

################################################################################
# Cluster IAM role
################################################################################

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "${var.cluster_name}-cluster-"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.tags, { Name = "${var.cluster_name}-cluster" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

################################################################################
# Security groups
################################################################################

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS control plane security group for ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.cluster_name}-cluster" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "node" {
  name_prefix = "${var.cluster_name}-node-"
  description = "Shared security group for ${var.cluster_name} worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-node"
    # Required so the in-tree cloud provider and the AWS LB controller can
    # discover the node security group.
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Control plane -> kubelet / extension API servers.
resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  security_group_id = aws_security_group.node.id
  description       = "Control plane to kubelet and webhooks"

  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_443" {
  security_group_id = aws_security_group.node.id
  description       = "Control plane to node HTTPS"

  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = local.tags
}

# Node-to-node traffic: pod networking, CoreDNS, service mesh sidecars.
resource "aws_vpc_security_group_ingress_rule" "node_from_node" {
  security_group_id = aws_security_group.node.id
  description       = "Node to node all traffic"

  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.node.id
  description       = "Node egress to everywhere"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = local.tags
}

# Nodes -> API server.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  security_group_id = aws_security_group.cluster.id
  description       = "Nodes to control plane API"

  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Control plane egress to everywhere"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster_additional" {
  for_each = var.cluster_security_group_additional_rules

  security_group_id = aws_security_group.cluster.id
  description       = each.value.description

  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = try(each.value.cidr_blocks[0], null)
  referenced_security_group_id = each.value.source_security_group_id

  tags = merge(local.tags, { Name = each.key })
}

resource "aws_vpc_security_group_ingress_rule" "node_additional" {
  for_each = var.node_security_group_additional_rules

  security_group_id = aws_security_group.node.id
  description       = each.value.description

  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = try(each.value.cidr_blocks[0], null)
  referenced_security_group_id = each.value.source_security_group_id

  tags = merge(local.tags, { Name = each.key })
}

################################################################################
# Control plane
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  count = length(var.enabled_cluster_log_types) > 0 ? 1 : 0

  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_in_days

  tags = merge(local.tags, { Name = "${var.cluster_name}-cluster-logs" })
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = local.control_plane_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  dynamic "encryption_config" {
    for_each = local.kms_key_arn != null ? [local.kms_key_arn] : []

    content {
      resources = ["secrets"]

      provider {
        key_arn = encryption_config.value
      }
    }
  }

  tags = merge(local.tags, { Name = var.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

################################################################################
# IRSA / OIDC provider
################################################################################

data "tls_certificate" "oidc" {
  count = var.enable_irsa ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "${var.cluster_name}-oidc" })
}

################################################################################
# Node group IAM roles
################################################################################

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  for_each = var.node_groups

  name_prefix        = substr("${var.cluster_name}-${each.key}-", 0, 32)
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policy_attachments

  role       = aws_iam_role.node[each.value.group].name
  policy_arn = each.value.policy_arn
}

################################################################################
# Managed node groups
################################################################################

resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix            = substr("${var.cluster_name}-${each.key}-", 0, 32)
  description            = "Launch template for ${var.cluster_name} node group ${each.key}"
  update_default_version = true

  vpc_security_group_ids = [aws_security_group.node.id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required, and hop limit 2 so pods on the host network can still
  # reach the metadata service when they legitimately need to.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node[each.key].arn
  subnet_ids      = coalesce(each.value.subnet_ids, var.subnet_ids)

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  ami_type       = each.value.ami_type
  labels         = each.value.labels

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable_percentage = each.value.max_unavailable_percentage
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })

  lifecycle {
    # desired_size is owned by the cluster autoscaler / karpenter once the node
    # group is live, so Terraform must not fight it on every plan.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

################################################################################
# Addons
################################################################################

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  addon_version               = each.value.addon_version
  service_account_role_arn    = each.value.service_account_role_arn
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  preserve                    = each.value.preserve

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })

  # Addons schedule onto nodes, so the node groups must exist first or the
  # addon install times out waiting for capacity.
  depends_on = [aws_eks_node_group.this]
}
