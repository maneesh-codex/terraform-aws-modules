# Example: Secure data platform

A data-tier stack built from the `vpc`, `rds-postgres`, `s3-bucket` and
`iam-irsa-role` modules, with the database deliberately unroutable from the
internet.

## What it builds

- A two-AZ VPC with public, private and intra tiers. The database goes in the
  **intra** subnets, whose route tables have no default route at all — not to an
  internet gateway, not to a NAT gateway.
- Multi-AZ PostgreSQL (in `prod`) with the RDS-managed Secrets Manager password,
  Performance Insights, enhanced monitoring, `pg_stat_statements`, query logging
  and baseline CloudWatch alarms.
- A KMS-encrypted data lake bucket with per-zone lifecycle rules (`raw/`,
  `curated/`, `scratch/`).
- An audit log bucket with ~7 year retention, receiving S3 access logs from the
  data lake.
- An IRSA role letting an EKS workload read/write the lake, use its KMS key, and
  read the database credential from Secrets Manager.

## Prerequisite

This example layers onto an **existing** EKS cluster rather than creating one —
which is the realistic shape, since the data platform and the cluster usually
have different lifecycles. You must supply the cluster's OIDC provider ARN:

```bash
terraform apply -var 'oidc_provider_arn=arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/ABC123'
```

If you ran the `eks-platform` example, take it from there:

```bash
terraform -chdir=../eks-platform output -raw oidc_provider_arn
```

You will also want to let the cluster's nodes reach the database:

```bash
-var 'additional_db_client_security_group_ids=["sg-0123456789abcdef0"]'
```

## Defence in depth

The security posture here is layered rather than relying on any single control:

1. **Routing** — intra subnets have no route off the VPC. A misconfigured
   security group cannot expose the database to the internet, because there is
   no path.
2. **Security groups** — RDS accepts connections only from the compute security
   group, referenced by ID rather than by CIDR range.
3. **Credentials** — the master password is generated and rotated by RDS inside
   Secrets Manager. It never enters Terraform state or plan output.
4. **Identity** — the workload authenticates via IRSA. No static AWS keys, and
   permissions are scoped to one service account in one namespace.
5. **Encryption** — storage encrypted at rest, TLS enforced on both buckets by
   bucket policy, data lake objects under a dedicated customer-managed key.
6. **Audit** — VPC flow logs retained a year, S3 access logs retained seven.

## Environment-driven defaults

| Setting | `prod` | everything else |
| --- | --- | --- |
| `multi_az` | `true` | `false` |
| `deletion_protection` | `true` | `false` |
| `skip_final_snapshot` | `false` | `true` |
| `backup_retention_period` | 35 days | 7 days |
| NAT gateways | One per AZ | Single shared gateway |
| Data lake `force_destroy` | `false` | `true` |

The audit bucket is never force-destroyed, in any environment.

## Connecting to the database

The workload reads the credential at startup:

```python
import boto3, json, psycopg

secret = json.loads(
    boto3.client("secretsmanager")
    .get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])["SecretString"]
)

conn = psycopg.connect(
    host=os.environ["DB_HOST"],
    dbname=os.environ["DB_NAME"],
    user=secret["username"],
    password=secret["password"],
    sslmode="require",
)
```

Pass `DB_SECRET_ARN` and `DB_HOST` from the `db_master_secret_arn` and
`db_endpoint` outputs.

Treat the master credential as break-glass: use it once to create
least-privilege application roles, then hand those to your services.

## Cleanup

```bash
terraform destroy
```

In `prod` shape both `deletion_protection` and the audit bucket's
`force_destroy = false` will block the destroy until you deliberately disable
them. That is the point.
