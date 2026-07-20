# S3 Bucket

An S3 bucket that is private, versioned and encrypted by default, with
declarative lifecycle rules.

## Defaults

Every default in this module is the secure one:

| Setting | Default | Why |
| --- | --- | --- |
| `versioning_enabled` | `true` | Recovery from accidental deletes and overwrites |
| `block_public_access` | `true` | All four public access block settings on |
| `object_ownership` | `BucketOwnerEnforced` | ACLs disabled entirely |
| `enforce_tls` | `true` | Bucket policy denies non-TLS requests |
| `force_destroy` | `false` | Terraform will not delete a bucket with objects in it |
| Encryption | SSE-S3, or SSE-KMS when a key is set | Encrypted at rest either way |

## Usage

```hcl
module "artifacts" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/s3-bucket?ref=v1.0.0"

  bucket_prefix = "platform-prod-artifacts-"

  versioning_enabled = true
  create_kms_key     = true # dedicated, rotating CMK

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
      id     = "archive-logs"
      prefix = "logs/"

      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]

      expiration_days = 365
    },
  ]

  tags = { Environment = "prod" }
}
```

## Encryption

Three modes:

- **SSE-S3 (default)** — leave `kms_key_arn` null and `create_kms_key` false.
- **Dedicated CMK** — set `create_kms_key = true`. The module creates a key with
  rotation enabled and an alias. Grant consumers `kms:Decrypt` and
  `kms:GenerateDataKey` on `kms_key_arn`.
- **Existing CMK** — pass `kms_key_arn`. Takes precedence over `create_kms_key`.

`bucket_key_enabled` defaults to `true` for SSE-KMS buckets, which cuts KMS
request costs substantially on high-volume buckets.

Note that some AWS log delivery services (S3 server access logging among them)
cannot write to a bucket encrypted with a customer-managed key. Use SSE-S3 for
those buckets.

## Lifecycle rules

Each rule takes an `id`, an optional `prefix`/`tags` filter, and any combination
of transitions and expirations. Rules acting on noncurrent versions require
versioning, which the module enforces through an explicit dependency.

Storage classes, cheapest-last: `STANDARD_IA`, `INTELLIGENT_TIERING`,
`ONEZONE_IA`, `GLACIER_IR`, `GLACIER`, `DEEP_ARCHIVE`. Minimum storage durations
apply — moving an object to `GLACIER` and deleting it a week later costs more
than leaving it in `STANDARD`.

## Notes

- Exactly one of `bucket` or `bucket_prefix` must be set; a `precondition`
  enforces this at plan time. Prefer `bucket_prefix` — bucket names are globally
  unique, and a prefix avoids collisions.
- Extra bucket policy statements go in `policy_statements` as objects; they are
  merged with the TLS-enforcement statement into a single policy.
- `force_destroy = true` is convenient for ephemeral environments and dangerous
  everywhere else.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_block_public_access"></a> [block\_public\_access](#input\_block\_public\_access) | Apply the full S3 public access block (all four settings). Disable only with a very good reason, such as a static website bucket. | `bool` | `true` | no |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Name of the S3 bucket. Must be globally unique. Mutually exclusive with `bucket_prefix`. | `string` | `null` | no |
| <a name="input_bucket_key_enabled"></a> [bucket\_key\_enabled](#input\_bucket\_key\_enabled) | Use an S3 bucket key to cut KMS request costs on SSE-KMS buckets. | `bool` | `true` | no |
| <a name="input_bucket_prefix"></a> [bucket\_prefix](#input\_bucket\_prefix) | Creates a bucket with a unique name beginning with this prefix. Mutually exclusive with `bucket`. | `string` | `null` | no |
| <a name="input_create_kms_key"></a> [create\_kms\_key](#input\_create\_kms\_key) | Create a dedicated, rotating KMS key for this bucket. Ignored when `kms_key_arn` is supplied. | `bool` | `false` | no |
| <a name="input_enforce_tls"></a> [enforce\_tls](#input\_enforce\_tls) | Attach a bucket policy statement denying any request that does not arrive over TLS. | `bool` | `true` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow Terraform to delete the bucket even when it still holds objects. Leave false outside of throwaway environments. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used for SSE-KMS. When null the module falls back to SSE-S3 (AES256) unless `create_kms_key` is true. | `string` | `null` | no |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | Waiting period before a scheduled KMS key deletion completes. | `number` | `30` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Lifecycle rules for the bucket. Each rule supports:<br/>  id                                     - unique rule identifier (required)<br/>  enabled                                - whether the rule is active (default true)<br/>  prefix                                 - object key prefix the rule applies to (default "", meaning all objects)<br/>  tags                                   - object tags the rule filters on<br/>  transitions                            - list of { days, storage\_class } for current versions<br/>  noncurrent\_version\_transitions         - list of { days, storage\_class } for previous versions<br/>  expiration\_days                        - delete current versions after N days<br/>  noncurrent\_version\_expiration\_days     - delete previous versions N days after they stop being current<br/>  abort\_incomplete\_multipart\_upload\_days - clean up abandoned multipart uploads after N days | <pre>list(object({<br/>    id                                     = string<br/>    enabled                                = optional(bool, true)<br/>    prefix                                 = optional(string, "")<br/>    tags                                   = optional(map(string), {})<br/>    expiration_days                        = optional(number)<br/>    noncurrent_version_expiration_days     = optional(number)<br/>    abort_incomplete_multipart_upload_days = optional(number)<br/>    transitions = optional(list(object({<br/>      days          = number<br/>      storage_class = string<br/>    })), [])<br/>    noncurrent_version_transitions = optional(list(object({<br/>      days          = number<br/>      storage_class = string<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_logging"></a> [logging](#input\_logging) | Server access logging target. Set to null to disable. | <pre>object({<br/>    target_bucket = string<br/>    target_prefix = optional(string, "")<br/>  })</pre> | `null` | no |
| <a name="input_mfa_delete"></a> [mfa\_delete](#input\_mfa\_delete) | Require MFA to permanently delete an object version. Can only be toggled by the bucket owner using root credentials. | `bool` | `false` | no |
| <a name="input_object_ownership"></a> [object\_ownership](#input\_object\_ownership) | Object ownership setting. BucketOwnerEnforced disables ACLs entirely and is the recommended modern default. | `string` | `"BucketOwnerEnforced"` | no |
| <a name="input_policy_statements"></a> [policy\_statements](#input\_policy\_statements) | Extra IAM policy statements (as JSON-encodable objects) merged into the bucket policy alongside the TLS statement. | `list(any)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Enable object versioning. Strongly recommended - it is the safety net behind lifecycle rules and accidental deletes. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the bucket. |
| <a name="output_bucket_domain_name"></a> [bucket\_domain\_name](#output\_bucket\_domain\_name) | Global domain name of the bucket. |
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | Name of the bucket. |
| <a name="output_bucket_region"></a> [bucket\_region](#output\_bucket\_region) | Region the bucket resides in. |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Region-specific domain name of the bucket. Prefer this over the global name to avoid cross-region redirects. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key protecting the bucket, or null when using SSE-S3. |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | ID of the KMS key created by this module, or null when no key was created. |
<!-- END_TF_DOCS -->
