# RDS PostgreSQL

A PostgreSQL instance with Multi-AZ support, a managed parameter group, Secrets
Manager credentials, encrypted storage, backups and optional baseline alarms.

## Password handling

Two mutually exclusive paths, selected by `manage_master_user_password`:

| Setting | Who owns the password | In Terraform state? | Rotation |
| --- | --- | --- | --- |
| `true` (default) | RDS, via its native Secrets Manager integration | **No** | Managed by RDS |
| `false` | This module, via `random_password` | Yes | Schedule only; needs a rotation Lambda |

Prefer the default. The password is generated inside RDS and never passes
through Terraform, which means it never lands in your state file or plan output.
The `false` path exists for cases where you need the credential in a specific
secret shape (`{username, password, host, port, dbname}`) that an existing
consumer already expects.

Either way, `master_user_secret_arn` gives you the secret ARN to grant read
access to.

## Usage

```hcl
module "postgres" {
  source = "github.com/maneesh-m/terraform-aws-modules//modules/rds-postgres?ref=v1.0.0"

  identifier     = "analytics-prod"
  engine_version = "16.4"
  instance_class = "db.r6g.xlarge"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnet_ids # no internet route

  # Grant access by security group, not CIDR.
  allowed_security_group_ids = [module.eks.node_security_group_id]

  db_name  = "analytics"
  username = "dbadmin"

  allocated_storage     = 100
  max_allocated_storage = 1000

  multi_az                = true
  deletion_protection     = true
  backup_retention_period = 35

  parameter_group_family = "postgres16"

  parameters = [
    { name = "log_min_duration_statement", value = "500" },
    { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
  ]

  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = { Environment = "prod" }
}
```

## Connecting from a pod

Grant the workload's IRSA role read access to the secret, then have the
application fetch it at startup:

```hcl
statement {
  effect    = "Allow"
  actions   = ["secretsmanager:GetSecretValue"]
  resources = [module.postgres.master_user_secret_arn]
}
```

For production, treat the master credential as a break-glass account: use it
once to create least-privilege application roles, and hand those to your
services rather than the master password.

## Parameter groups

`parameter_group_family` must match the major version in `engine_version` —
`postgres16` for `16.x`, `postgres15` for `15.x`. A mismatch fails at apply
time, not at plan time.

Parameters with `apply_method = "pending-reboot"` (anything touching
`shared_preload_libraries`, `max_connections`, and similar) do not take effect
until the instance reboots. Set `apply_immediately = true` or wait for the
maintenance window.

## Notes

- Storage is always encrypted. `kms_key_arn` selects a customer-managed key;
  otherwise the AWS-managed RDS key is used.
- `final_snapshot_identifier` embeds a timestamp and is in `ignore_changes`,
  so it does not produce a spurious diff on every plan.
- `backup_window` and `maintenance_window` must not overlap; RDS rejects the
  configuration if they do.
- Enhanced monitoring (`monitoring_interval > 0`) creates its own IAM role
  automatically.
- Put the instance in intra subnets. It has no reason to reach the internet,
  and `publicly_accessible` defaults to `false` for the same reason.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.5 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_metric_alarm.connections](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.free_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_rotation.master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation) | resource |
| [aws_secretsmanager_secret_version.master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr_blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_password.master](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.monitoring_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | ARNs notified when an alarm fires, e.g. an SNS topic. | `list(string)` | `[]` | no |
| <a name="input_allocated_storage"></a> [allocated\_storage](#input\_allocated\_storage) | Initial storage in GiB. | `number` | `50` | no |
| <a name="input_allow_major_version_upgrade"></a> [allow\_major\_version\_upgrade](#input\_allow\_major\_version\_upgrade) | Permit major version upgrades. Requires a compatible parameter group family. | `bool` | `false` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | CIDR blocks permitted to connect on the database port. Prefer `allowed_security_group_ids` where possible. | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs permitted to connect on the database port. This is the preferred way to grant access. | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications immediately instead of waiting for the maintenance window. | `bool` | `false` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Automatically apply minor engine upgrades during the maintenance window. | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Days of automated backups to retain. 0 disables backups entirely. | `number` | `14` | no |
| <a name="input_backup_window"></a> [backup\_window](#input\_backup\_window) | Daily backup window in UTC, `hh:mm-hh:mm`. | `string` | `"03:00-04:00"` | no |
| <a name="input_copy_tags_to_snapshot"></a> [copy\_tags\_to\_snapshot](#input\_copy\_tags\_to\_snapshot) | Copy instance tags onto snapshots. | `bool` | `true` | no |
| <a name="input_cpu_utilization_alarm_threshold"></a> [cpu\_utilization\_alarm\_threshold](#input\_cpu\_utilization\_alarm\_threshold) | CPU utilization percentage that triggers the CPU alarm. | `number` | `80` | no |
| <a name="input_create_cloudwatch_alarms"></a> [create\_cloudwatch\_alarms](#input\_create\_cloudwatch\_alarms) | Create baseline CloudWatch alarms for CPU, free storage and connection count. | `bool` | `false` | no |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Name of the database created on the instance. | `string` | `"app"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block accidental deletion of the instance. | `bool` | `true` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | Log types exported to CloudWatch Logs. | `list(string)` | <pre>[<br/>  "postgresql",<br/>  "upgrade"<br/>]</pre> | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | PostgreSQL engine version. Use a major version alone (e.g. "16") to track the latest minor release. | `string` | `"16.4"` | no |
| <a name="input_free_storage_alarm_threshold_bytes"></a> [free\_storage\_alarm\_threshold\_bytes](#input\_free\_storage\_alarm\_threshold\_bytes) | Free storage in bytes below which the storage alarm fires. Defaults to 10 GiB. | `number` | `10737418240` | no |
| <a name="input_identifier"></a> [identifier](#input\_identifier) | Identifier for the RDS instance. Also used as a name prefix for supporting resources. | `string` | n/a | yes |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class. | `string` | `"db.t4g.medium"` | no |
| <a name="input_iops"></a> [iops](#input\_iops) | Provisioned IOPS. Only valid for io1/io2, or gp3 above 400 GiB. | `number` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for storage encryption. Defaults to the AWS-managed RDS key when null. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Weekly maintenance window in UTC, `ddd:hh:mm-ddd:hh:mm`. Must not overlap the backup window. | `string` | `"sun:04:30-sun:05:30"` | no |
| <a name="input_manage_master_user_password"></a> [manage\_master\_user\_password](#input\_manage\_master\_user\_password) | Let RDS generate and rotate the master password in Secrets Manager (the managed integration).<br/>When false the module generates a random password itself and stores it in a Secrets Manager<br/>secret it owns. The managed integration is preferred - the password never passes through<br/>Terraform state. | `bool` | `true` | no |
| <a name="input_master_user_secret_kms_key_arn"></a> [master\_user\_secret\_kms\_key\_arn](#input\_master\_user\_secret\_kms\_key\_arn) | KMS key ARN protecting the master user secret. Defaults to the AWS-managed key when null. | `string` | `null` | no |
| <a name="input_max_allocated_storage"></a> [max\_allocated\_storage](#input\_max\_allocated\_storage) | Upper bound in GiB for storage autoscaling. Set to 0 to disable autoscaling. | `number` | `500` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring\_interval) | Enhanced monitoring granularity in seconds. 0 disables it; valid values are 0, 1, 5, 10, 15, 30 and 60. | `number` | `60` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | Deploy a synchronous standby in a second AZ. Roughly doubles cost; required for most production workloads. | `bool` | `true` | no |
| <a name="input_parameter_group_family"></a> [parameter\_group\_family](#input\_parameter\_group\_family) | Parameter group family, e.g. `postgres16`. Must match the major version in `engine_version`. | `string` | `"postgres16"` | no |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Parameters applied to the generated DB parameter group. `apply_method` is `immediate` or `pending-reboot`. | <pre>list(object({<br/>    name         = string<br/>    value        = string<br/>    apply_method = optional(string, "immediate")<br/>  }))</pre> | <pre>[<br/>  {<br/>    "apply_method": "immediate",<br/>    "name": "log_min_duration_statement",<br/>    "value": "1000"<br/>  },<br/>  {<br/>    "apply_method": "immediate",<br/>    "name": "log_connections",<br/>    "value": "1"<br/>  },<br/>  {<br/>    "apply_method": "immediate",<br/>    "name": "log_disconnections",<br/>    "value": "1"<br/>  }<br/>]</pre> | no |
| <a name="input_password_rotation_days"></a> [password\_rotation\_days](#input\_password\_rotation\_days) | Rotation interval in days for the self-managed secret. Only used when `manage_master_user_password` is false. | `number` | `30` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Enable Performance Insights. | `bool` | `true` | no |
| <a name="input_performance_insights_retention_period"></a> [performance\_insights\_retention\_period](#input\_performance\_insights\_retention\_period) | Performance Insights retention in days. 7 is free tier; other valid values are 731 or a multiple of 31. | `number` | `7` | no |
| <a name="input_port"></a> [port](#input\_port) | TCP port the database listens on. | `number` | `5432` | no |
| <a name="input_publicly_accessible"></a> [publicly\_accessible](#input\_publicly\_accessible) | Assign a public IP to the instance. Leave false. | `bool` | `false` | no |
| <a name="input_secret_recovery_window_in_days"></a> [secret\_recovery\_window\_in\_days](#input\_secret\_recovery\_window\_in\_days) | Recovery window for the self-managed secret. 0 deletes it immediately. | `number` | `7` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Skip the final snapshot on destroy. Only sensible for ephemeral environments. | `bool` | `false` | no |
| <a name="input_storage_throughput"></a> [storage\_throughput](#input\_storage\_throughput) | Storage throughput in MiB/s. gp3 only. | `number` | `null` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Storage type. gp3 is the sensible default; io1/io2 only when you have a measured IOPS requirement. | `string` | `"gp3"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the DB subnet group. Use private or intra subnets across at least two AZs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | Master username. Note that `admin`, `rdsadmin` and `postgres` are reserved by RDS in some configurations. | `string` | `"dbadmin"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC hosting the instance. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_alarm_arns"></a> [cloudwatch\_alarm\_arns](#output\_cloudwatch\_alarm\_arns) | ARNs of the baseline CloudWatch alarms, when enabled. |
| <a name="output_db_instance_address"></a> [db\_instance\_address](#output\_db\_instance\_address) | Hostname of the RDS instance. |
| <a name="output_db_instance_arn"></a> [db\_instance\_arn](#output\_db\_instance\_arn) | ARN of the RDS instance. |
| <a name="output_db_instance_availability_zone"></a> [db\_instance\_availability\_zone](#output\_db\_instance\_availability\_zone) | AZ hosting the primary instance. |
| <a name="output_db_instance_endpoint"></a> [db\_instance\_endpoint](#output\_db\_instance\_endpoint) | Connection endpoint in `host:port` form. |
| <a name="output_db_instance_id"></a> [db\_instance\_id](#output\_db\_instance\_id) | Identifier of the RDS instance. |
| <a name="output_db_instance_multi_az"></a> [db\_instance\_multi\_az](#output\_db\_instance\_multi\_az) | Whether the instance is deployed Multi-AZ. |
| <a name="output_db_instance_name"></a> [db\_instance\_name](#output\_db\_instance\_name) | Name of the initial database. |
| <a name="output_db_instance_port"></a> [db\_instance\_port](#output\_db\_instance\_port) | Port the database listens on. |
| <a name="output_db_instance_resource_id"></a> [db\_instance\_resource\_id](#output\_db\_instance\_resource\_id) | Region-unique resource ID. Use this in IAM database authentication policies. |
| <a name="output_db_instance_username"></a> [db\_instance\_username](#output\_db\_instance\_username) | Master username. |
| <a name="output_db_subnet_group_name"></a> [db\_subnet\_group\_name](#output\_db\_subnet\_group\_name) | Name of the DB subnet group. |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the Secrets Manager secret holding the master credentials, whichever path created it.<br/>With the RDS-managed integration this is the secret RDS owns and rotates. |
| <a name="output_monitoring_role_arn"></a> [monitoring\_role\_arn](#output\_monitoring\_role\_arn) | ARN of the enhanced monitoring IAM role, or null when monitoring is disabled. |
| <a name="output_parameter_group_name"></a> [parameter\_group\_name](#output\_parameter\_group\_name) | Name of the DB parameter group. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the security group in front of the instance. |
<!-- END_TF_DOCS -->
