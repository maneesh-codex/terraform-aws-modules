# terraform-aws-modules

Reusable Terraform modules for AWS platform infrastructure — VPC, EKS, RDS
PostgreSQL, S3 and IRSA roles — plus runnable examples that wire them together
into complete stacks.

Every module is production-shaped rather than demo-shaped: secure defaults,
validated inputs, consistent tagging, and comments explaining the decisions that
are not obvious from the resource names.

[![CI](https://github.com/maneesh-m/terraform-aws-modules/actions/workflows/ci.yml/badge.svg)](https://github.com/maneesh-m/terraform-aws-modules/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Requirements

| Name | Version |
| --- | --- |
| terraform | >= 1.5 |
| aws | ~> 5.0 |
| tls | ~> 4.0 (eks module only) |
| random | ~> 3.5 (rds-postgres module only) |

## Modules

| Module | Purpose |
| --- | --- |
| [`vpc`](modules/vpc) | Multi-AZ VPC with public / private / intra subnet tiers, optional NAT gateways, and flow logs |
| [`eks`](modules/eks) | EKS cluster with managed node groups, IRSA/OIDC provider, addons and security groups |
| [`rds-postgres`](modules/rds-postgres) | PostgreSQL with Multi-AZ, parameter groups, Secrets Manager credentials and backups |
| [`s3-bucket`](modules/s3-bucket) | Private, versioned, encrypted bucket with lifecycle rules |
| [`iam-irsa-role`](modules/iam-irsa-role) | IAM role assumable by a Kubernetes service account via OIDC |

## Quick start

```hcl
module "vpc" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/vpc?ref=v1.0.0"

  name       = "platform-prod"
  cidr_block = "10.20.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  intra_subnets   = ["10.20.20.0/24", "10.20.21.0/24", "10.20.22.0/24"]

  enable_nat_gateway = true
  enable_flow_logs   = true

  tags = local.tags
}

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
    }
  }

  tags = local.tags
}

module "postgres" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/rds-postgres?ref=v1.0.0"

  identifier = "platform-prod-pg"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnet_ids

  # Only the cluster's nodes may connect.
  allowed_security_group_ids = [module.eks.node_security_group_id]

  multi_az                    = true
  manage_master_user_password = true

  tags = local.tags
}

module "app_irsa" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/iam-irsa-role?ref=v1.0.0"

  name                       = "platform-prod-app"
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = ["applications:app"]

  inline_policy = data.aws_iam_policy_document.app.json

  tags = local.tags
}
```

## Examples

| Example | What it demonstrates |
| --- | --- |
| [`eks-platform`](examples/eks-platform) | Full container platform: VPC, EKS with on-demand and spot node groups, IRSA roles for the LB controller / autoscaler / EBS CSI driver, and an artifacts bucket |
| [`secure-data-platform`](examples/secure-data-platform) | Data tier: Multi-AZ PostgreSQL in unroutable intra subnets, KMS-encrypted data lake, audit log bucket, and an IRSA role for the pipeline workload |

Both examples are runnable:

```bash
cd examples/eks-platform
terraform init
terraform plan
```

## Design principles

**Secure by default.** Public access blocked, encryption on, TLS enforced,
deletion protection enabled, private API endpoints. The insecure option is
always available, but it is always the one you have to ask for.

**Fail at plan time, not apply time.** Inputs carry `validation` blocks so a bad
CIDR, an out-of-range retention period or an inconsistent autoscaling bound is
caught before anything is created.

**Layered network tiers.** Public for load balancers, private for compute, and
intra for data. Intra subnets have no default route whatsoever, so a database
placed there cannot reach the internet even if a security group is wrong.

**Credentials never touch state.** The RDS module defaults to the managed
Secrets Manager integration, where the password is generated inside RDS. IRSA
means workloads get scoped, short-lived credentials with no static keys.

**Consistent tagging.** Every module takes `tags` and merges it into every
taggable resource, alongside a `terraform-module` tag identifying the source.

## Module inputs and outputs at a glance

### `vpc`

| Key inputs | | Key outputs | |
| --- | --- | --- | --- |
| `name` | Name prefix | `vpc_id` | VPC ID |
| `cidr_block` | VPC CIDR | `public_subnet_ids` | Public subnet IDs |
| `azs` | Availability Zones | `private_subnet_ids` | Private subnet IDs |
| `public_subnets` / `private_subnets` / `intra_subnets` | Per-tier CIDRs | `intra_subnet_ids` | Intra subnet IDs |
| `enable_nat_gateway` / `single_nat_gateway` | NAT topology | `nat_public_ips` | NAT egress IPs, for allow-listing |
| `enable_flow_logs` | Flow logs to CloudWatch | `flow_log_cloudwatch_log_group_name` | Log group name |

### `eks`

| Key inputs | | Key outputs | |
| --- | --- | --- | --- |
| `cluster_name` | Cluster name | `cluster_endpoint` | API server endpoint |
| `cluster_version` | Kubernetes version | `cluster_certificate_authority_data` | CA cert, for kubeconfig |
| `vpc_id` / `subnet_ids` | Placement | `oidc_provider_arn` | Feeds `iam-irsa-role` |
| `node_groups` | Map of managed node groups | `node_security_group_id` | For RDS ingress rules |
| `cluster_addons` | Map of EKS addons | `node_group_iam_role_arns` | Node role ARNs |
| `endpoint_public_access` | API exposure | `kubeconfig_command` | Ready-to-run kubectl setup |

### `rds-postgres`

| Key inputs | | Key outputs | |
| --- | --- | --- | --- |
| `identifier` | Instance identifier | `db_instance_endpoint` | `host:port` |
| `engine_version` / `parameter_group_family` | Must match major version | `db_instance_address` | Hostname |
| `vpc_id` / `subnet_ids` | Placement | `master_user_secret_arn` | Secrets Manager ARN |
| `allowed_security_group_ids` | Who may connect | `security_group_id` | The DB security group |
| `multi_az` | Synchronous standby | `db_instance_resource_id` | For IAM DB auth policies |
| `manage_master_user_password` | RDS-managed secret | `parameter_group_name` | Parameter group |

### `s3-bucket`

| Key inputs | | Key outputs | |
| --- | --- | --- | --- |
| `bucket` / `bucket_prefix` | Exactly one required | `bucket_id` | Bucket name |
| `versioning_enabled` | Object versioning | `bucket_arn` | Bucket ARN |
| `create_kms_key` / `kms_key_arn` | Encryption mode | `kms_key_arn` | Key protecting the bucket |
| `lifecycle_rules` | Transitions and expirations | `bucket_regional_domain_name` | Regional endpoint |
| `enforce_tls` | Deny non-TLS requests | | |

### `iam-irsa-role`

| Key inputs | | Key outputs | |
| --- | --- | --- | --- |
| `name` | Role name or prefix | `iam_role_arn` | Role ARN for the annotation |
| `oidc_provider_arn` | From the `eks` module | `iam_role_name` | Role name |
| `namespace_service_accounts` | `namespace:sa` pairs | `service_account_annotation` | Ready-to-paste annotation map |
| `policy_arns` / `inline_policy` | Permissions | `oidc_issuer` | Derived issuer |

Full input and output tables live in each module's README.

## Development

```bash
pre-commit install
tflint --init
pre-commit run --all-files
```

CI checks formatting, runs `terraform validate` against every module and
example, lints with tflint, and verifies the terraform-docs blocks are current.
It does not run `plan` or `apply` — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

Author: **Maneesh M**
