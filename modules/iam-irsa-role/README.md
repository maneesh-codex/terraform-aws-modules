# IAM IRSA Role

An IAM role a Kubernetes service account can assume through the cluster's OIDC
provider — IAM Roles for Service Accounts (IRSA).

## How IRSA works

The kubelet projects a signed JWT into the pod. The AWS SDK exchanges that token
for temporary credentials via `sts:AssumeRoleWithWebIdentity`. The role's trust
policy decides which service accounts are allowed, by matching the token's `sub`
claim against `system:serviceaccount:<namespace>:<name>`.

The result is per-workload credentials with no static keys and no node-level
permission sharing.

## Usage

```hcl
module "external_dns_irsa" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/iam-irsa-role?ref=v1.0.0"

  name              = "platform-prod-external-dns"
  description       = "external-dns for platform-prod"
  oidc_provider_arn = module.eks.oidc_provider_arn

  namespace_service_accounts = ["kube-system:external-dns"]

  inline_policy = data.aws_iam_policy_document.external_dns.json

  tags = { Environment = "prod" }
}
```

Then annotate the service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::111122223333:role/platform-prod-external-dns-a1b2c3
```

The `service_account_annotation` output produces that annotation map directly,
which is handy if you are rendering the manifest from Terraform or passing it
into a Helm release.

## Attaching permissions

Managed policies:

```hcl
policy_arns = [
  "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
]
```

Inline policy, built with `aws_iam_policy_document`:

```hcl
data "aws_iam_policy_document" "app" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.bucket.bucket_arn}/*"]
  }
}
```

Both can be used together.

## Wildcards

`namespace_service_accounts` accepts `*` in either half:

```hcl
namespace_service_accounts = ["observability:*"]      # any SA in that namespace
namespace_service_accounts = ["*:prometheus"]         # that SA in any namespace
```

A wildcard switches the trust policy condition from `StringEquals` to
`StringLike`. This is a real widening of trust — `observability:*` means anyone
who can create a service account in that namespace can assume the role. Keep the
scope as narrow as the workload allows, and avoid `*:*` entirely.

The `aud` claim is always pinned to `sts.amazonaws.com` with `StringEquals`,
regardless of subject wildcards, so a token issued for another audience cannot
be replayed against this role.

## Notes

- `use_name_prefix` defaults to `true`, so AWS appends a unique suffix. This
  avoids collisions when a role is replaced, since IAM role names must be unique
  and deletion is not instantaneous.
- The OIDC issuer used in the trust policy conditions is derived from
  `oidc_provider_arn`; you do not need to pass the issuer URL separately.
- The provider ARN comes from the `eks` module's `oidc_provider_arn` output,
  which requires `enable_irsa = true` on that module.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | Description attached to the IAM role. | `string` | `"IAM role for a Kubernetes service account (IRSA)"` | no |
| <a name="input_force_detach_policies"></a> [force\_detach\_policies](#input\_force\_detach\_policies) | Force detaching any attached policies before destroying the role. | `bool` | `true` | no |
| <a name="input_inline_policy"></a> [inline\_policy](#input\_inline\_policy) | Inline policy document (JSON) attached to the role. Use `data.aws_iam_policy_document` to build it. | `string` | `null` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration in seconds for the role. | `number` | `3600` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the IAM role. Used as a prefix when `use_name_prefix` is true. | `string` | n/a | yes |
| <a name="input_namespace_service_accounts"></a> [namespace\_service\_accounts](#input\_namespace\_service\_accounts) | Kubernetes service accounts allowed to assume this role, in `namespace:serviceaccount` form.<br/>Both halves support `*` as a wildcard, e.g. `observability:*`. Wildcards force the trust policy<br/>to use StringLike instead of StringEquals, so keep them as narrow as you can. | `list(string)` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster's IAM OIDC provider, e.g. the `oidc_provider_arn` output of the eks module. | `string` | n/a | yes |
| <a name="input_path"></a> [path](#input\_path) | IAM path for the role. | `string` | `"/"` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of a policy used as the permissions boundary for the role. | `string` | `null` | no |
| <a name="input_policy_arns"></a> [policy\_arns](#input\_policy\_arns) | ARNs of existing managed policies to attach to the role. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| <a name="input_use_name_prefix"></a> [use\_name\_prefix](#input\_use\_name\_prefix) | Treat `name` as a prefix and let AWS append a unique suffix. Helps avoid name collisions on role replacement. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the IAM role. Annotate the service account with `eks.amazonaws.com/role-arn: <this value>`. |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the IAM role. |
| <a name="output_iam_role_unique_id"></a> [iam\_role\_unique\_id](#output\_iam\_role\_unique\_id) | Stable unique ID of the IAM role. |
| <a name="output_oidc_issuer"></a> [oidc\_issuer](#output\_oidc\_issuer) | OIDC issuer host/path derived from the provider ARN, as used in the trust policy conditions. |
| <a name="output_service_account_annotation"></a> [service\_account\_annotation](#output\_service\_account\_annotation) | Ready-to-use annotation map for the Kubernetes service account manifest. |
<!-- END_TF_DOCS -->
