# EKS

An EKS cluster with managed node groups, an IAM OIDC provider for IRSA, managed
addons and a sensible security group topology.

## What you get

- **Control plane** with envelope encryption of Kubernetes secrets via a
  dedicated, rotating KMS key, and control plane logs shipped to CloudWatch.
- **Managed node groups** driven by a map, each with its own IAM role, launch
  template, EBS encryption, IMDSv2 enforcement and optional taints/labels.
- **IRSA**: an IAM OIDC identity provider whose ARN feeds straight into the
  `iam-irsa-role` module.
- **Security groups**: separate cluster and node groups with the minimum rules
  needed for kubelet, webhooks, node-to-node pod traffic and API access.
- **Addons**: `coredns`, `kube-proxy` and `vpc-cni` by default, installed after
  the node groups exist so they have capacity to schedule onto.

## Usage

```hcl
module "eks" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/eks?ref=v1.0.0"

  cluster_name    = "platform-prod"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = false

  node_groups = {
    general = {
      instance_types = ["m6i.large"]
      desired_size   = 3
      min_size       = 3
      max_size       = 6
      disk_size      = 100
      labels         = { workload = "general" }
    }

    spot = {
      instance_types = ["m6i.large", "m5.large", "m5a.large"]
      capacity_type  = "SPOT"
      desired_size   = 2
      min_size       = 0
      max_size       = 10

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
  }

  tags = { Environment = "prod" }
}
```

## Wiring up IRSA

```hcl
module "external_dns_irsa" {
  source = "../iam-irsa-role"

  name                       = "platform-prod-external-dns"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["kube-system:external-dns"]
  inline_policy              = data.aws_iam_policy_document.external_dns.json
}
```

Then annotate the service account with
`eks.amazonaws.com/role-arn: <module.external_dns_irsa.iam_role_arn>`.

## Private API endpoints

The default is `endpoint_public_access = false`, which means `kubectl` only
works from inside the VPC. Reach it through a VPN, a bastion, or an SSM port
forward:

```bash
aws ssm start-session --target <bastion-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<cluster-endpoint>"],"portNumber":["443"],"localPortNumber":["8443"]}'
```

If you need public access, set `endpoint_public_access = true` and narrow
`public_access_cidrs` to your office and CI egress ranges rather than leaving
it at `0.0.0.0/0`.

## Notes

- `desired_size` is in `ignore_changes` on the node groups. Once the cluster
  autoscaler or Karpenter owns capacity, Terraform must not fight it on every
  plan. Change `min_size`/`max_size` to move the bounds.
- Node launch templates enforce IMDSv2 (`http_tokens = "required"`) with a hop
  limit of 2, so host-network pods can still reach the metadata service.
- Addons depend on the node groups. An addon with no schedulable capacity will
  time out during install, which is why the dependency is explicit.
- `authentication_mode` defaults to `API_AND_CONFIG_MAP` for compatibility with
  existing `aws-auth` ConfigMap workflows. New clusters should prefer `API`.
- The `tls` provider is used once, to read the OIDC issuer's certificate
  thumbprint when creating the identity provider.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.cluster_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.node_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_from_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_from_cluster_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_from_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.cluster_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [tls_certificate.oidc](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | Cluster access management mode: API, API\_AND\_CONFIG\_MAP or CONFIG\_MAP. API is the modern default and enables EKS access entries. | `string` | `"API_AND_CONFIG_MAP"` | no |
| <a name="input_bootstrap_cluster_creator_admin_permissions"></a> [bootstrap\_cluster\_creator\_admin\_permissions](#input\_bootstrap\_cluster\_creator\_admin\_permissions) | Grant the IAM principal running Terraform cluster-admin via an access entry. | `bool` | `true` | no |
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | EKS managed addons, keyed by addon name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, ...).<br/>Each entry supports `addon_version`, `service_account_role_arn`, `configuration_values`,<br/>`resolve_conflicts_on_create` and `resolve_conflicts_on_update`. Leave `addon_version` null<br/>to let EKS pick the default version for the cluster's Kubernetes release. | <pre>map(object({<br/>    addon_version               = optional(string)<br/>    service_account_role_arn    = optional(string)<br/>    configuration_values        = optional(string)<br/>    resolve_conflicts_on_create = optional(string, "OVERWRITE")<br/>    resolve_conflicts_on_update = optional(string, "OVERWRITE")<br/>    preserve                    = optional(bool, true)<br/>  }))</pre> | <pre>{<br/>  "coredns": {},<br/>  "kube-proxy": {},<br/>  "vpc-cni": {}<br/>}</pre> | no |
| <a name="input_cluster_encryption_kms_key_arn"></a> [cluster\_encryption\_kms\_key\_arn](#input\_cluster\_encryption\_kms\_key\_arn) | KMS key ARN used for envelope encryption of Kubernetes secrets. When null a dedicated key is created if `create_kms_key` is true. | `string` | `null` | no |
| <a name="input_cluster_log_retention_in_days"></a> [cluster\_log\_retention\_in\_days](#input\_cluster\_log\_retention\_in\_days) | Retention for the control plane CloudWatch Logs group. | `number` | `90` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. | `string` | n/a | yes |
| <a name="input_cluster_security_group_additional_rules"></a> [cluster\_security\_group\_additional\_rules](#input\_cluster\_security\_group\_additional\_rules) | Extra ingress rules on the cluster security group. Map key is an arbitrary rule name; each value supports:<br/>  description, from\_port, to\_port, protocol, cidr\_blocks, source\_security\_group\_id | <pre>map(object({<br/>    description              = optional(string, "Managed by Terraform")<br/>    from_port                = number<br/>    to_port                  = number<br/>    protocol                 = optional(string, "tcp")<br/>    cidr_blocks              = optional(list(string))<br/>    source_security_group_id = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes minor version for the control plane, e.g. "1.31". | `string` | `"1.31"` | no |
| <a name="input_control_plane_subnet_ids"></a> [control\_plane\_subnet\_ids](#input\_control\_plane\_subnet\_ids) | Subnet IDs for the control plane ENIs. Defaults to `subnet_ids` when empty. | `list(string)` | `[]` | no |
| <a name="input_create_kms_key"></a> [create\_kms\_key](#input\_create\_kms\_key) | Create a dedicated, rotating KMS key for envelope encryption of Kubernetes secrets. | `bool` | `true` | no |
| <a name="input_enable_irsa"></a> [enable\_irsa](#input\_enable\_irsa) | Create the IAM OIDC identity provider so service accounts can assume IAM roles. | `bool` | `true` | no |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | Control plane log types shipped to CloudWatch Logs. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_private_access"></a> [endpoint\_private\_access](#input\_endpoint\_private\_access) | Expose the Kubernetes API endpoint inside the VPC. | `bool` | `true` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Expose the Kubernetes API endpoint to the internet. | `bool` | `false` | no |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Managed node groups, keyed by name. Each group supports:<br/>  instance\_types  - EC2 instance types (default ["t3.large"])<br/>  capacity\_type   - ON\_DEMAND or SPOT (default ON\_DEMAND)<br/>  ami\_type        - AL2023\_x86\_64\_STANDARD, BOTTLEROCKET\_x86\_64, ... (default AL2023\_x86\_64\_STANDARD)<br/>  desired\_size / min\_size / max\_size - autoscaling bounds<br/>  disk\_size       - root volume size in GiB<br/>  subnet\_ids      - override the cluster-level subnets for this group<br/>  labels / taints - Kubernetes labels and taints<br/>  max\_unavailable\_percentage - rolling update budget<br/>  additional\_policy\_arns     - extra IAM policies for the node role | <pre>map(object({<br/>    instance_types             = optional(list(string), ["t3.large"])<br/>    capacity_type              = optional(string, "ON_DEMAND")<br/>    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")<br/>    desired_size               = optional(number, 2)<br/>    min_size                   = optional(number, 1)<br/>    max_size                   = optional(number, 4)<br/>    disk_size                  = optional(number, 50)<br/>    subnet_ids                 = optional(list(string))<br/>    labels                     = optional(map(string), {})<br/>    max_unavailable_percentage = optional(number, 33)<br/>    additional_policy_arns     = optional(list(string), [])<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | <pre>{<br/>  "default": {}<br/>}</pre> | no |
| <a name="input_node_security_group_additional_rules"></a> [node\_security\_group\_additional\_rules](#input\_node\_security\_group\_additional\_rules) | Extra ingress rules on the shared node security group. Same shape as `cluster_security_group_additional_rules`. | <pre>map(object({<br/>    description              = optional(string, "Managed by Terraform")<br/>    from_port                = number<br/>    to_port                  = number<br/>    protocol                 = optional(string, "tcp")<br/>    cidr_blocks              = optional(list(string))<br/>    source_security_group_id = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_public_access_cidrs"></a> [public\_access\_cidrs](#input\_public\_access\_cidrs) | CIDR blocks permitted to reach the public API endpoint. Ignored when `endpoint_public_access` is false. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the worker nodes. These should normally be private subnets across at least two AZs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC hosting the cluster. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_addon_versions"></a> [cluster\_addon\_versions](#output\_cluster\_addon\_versions) | Resolved versions of the installed EKS addons, keyed by addon name. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the EKS cluster. |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64-encoded CA certificate for the cluster. Feed this to the kubernetes/helm providers or kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | HTTPS endpoint of the Kubernetes API server. |
| <a name="output_cluster_iam_role_arn"></a> [cluster\_iam\_role\_arn](#output\_cluster\_iam\_role\_arn) | ARN of the IAM role assumed by the EKS control plane. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_platform_version"></a> [cluster\_platform\_version](#output\_cluster\_platform\_version) | EKS platform version of the cluster. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | ID of the security group attached to the control plane ENIs. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | Kubernetes version running on the control plane. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key used for secret envelope encryption, or null when disabled. |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Convenience command to write a kubeconfig entry for this cluster. |
| <a name="output_node_group_arns"></a> [node\_group\_arns](#output\_node\_group\_arns) | ARNs of the managed node groups, keyed by node group name. |
| <a name="output_node_group_autoscaling_group_names"></a> [node\_group\_autoscaling\_group\_names](#output\_node\_group\_autoscaling\_group\_names) | Autoscaling group names backing each managed node group. |
| <a name="output_node_group_iam_role_arns"></a> [node\_group\_iam\_role\_arns](#output\_node\_group\_iam\_role\_arns) | IAM role ARNs of the managed node groups, keyed by node group name. |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | ID of the shared worker node security group. Reference this from RDS or other backing services to allow pod traffic. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL of the cluster. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC provider. Pass this into the iam-irsa-role module. |
<!-- END_TF_DOCS -->
