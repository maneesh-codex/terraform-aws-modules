locals {
  tags = merge(var.tags, { "terraform-module" = "iam-irsa-role" })

  # arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/ABC
  # becomes                                 oidc.eks.eu-west-1.amazonaws.com/id/ABC
  oidc_issuer = replace(var.oidc_provider_arn, "/^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:oidc-provider\\//", "")

  subjects = [for sa in var.namespace_service_accounts : "system:serviceaccount:${sa}"]

  # A subject containing a wildcard cannot be matched with StringEquals, so we
  # split the list and emit one condition block for each comparison operator.
  exact_subjects    = [for s in local.subjects : s if !strcontains(s, "*")]
  wildcard_subjects = [for s in local.subjects : s if strcontains(s, "*")]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "EKSServiceAccountAssumeRoleWithWebIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Pin the audience so the token cannot be replayed against another service.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    dynamic "condition" {
      for_each = length(local.exact_subjects) > 0 ? [local.exact_subjects] : []

      content {
        test     = "StringEquals"
        variable = "${local.oidc_issuer}:sub"
        values   = condition.value
      }
    }

    dynamic "condition" {
      for_each = length(local.wildcard_subjects) > 0 ? [local.wildcard_subjects] : []

      content {
        test     = "StringLike"
        variable = "${local.oidc_issuer}:sub"
        values   = condition.value
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name        = var.use_name_prefix ? null : var.name
  name_prefix = var.use_name_prefix ? "${var.name}-" : null

  description           = var.description
  path                  = var.path
  assume_role_policy    = data.aws_iam_policy_document.assume_role.json
  permissions_boundary  = var.permissions_boundary_arn
  max_session_duration  = var.max_session_duration
  force_detach_policies = var.force_detach_policies

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy != null ? 1 : 0

  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.id
  policy      = var.inline_policy
}
