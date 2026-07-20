data "aws_partition" "current" {}

locals {
  tags = merge(var.tags, { "terraform-module" = "rds-postgres" })

  # When the managed Secrets Manager integration is off we generate and own the
  # password ourselves.
  self_managed_password = !var.manage_master_user_password
}

################################################################################
# Networking
################################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.identifier}-"
  description = "Subnet group for ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.identifier}-subnet-group" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-rds-"
  description = "Security group for RDS PostgreSQL instance ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.identifier}-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL access from ${each.value}"

  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr_blocks" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL access from ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = var.port
  to_port     = var.port

  tags = local.tags
}

################################################################################
# Parameter group
################################################################################

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-"
  description = "Parameter group for ${var.identifier}"
  family      = var.parameter_group_family

  dynamic "parameter" {
    for_each = var.parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, { Name = "${var.identifier}-params" })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Self-managed master password (only when the RDS-managed secret is disabled)
################################################################################

resource "random_password" "master" {
  count = local.self_managed_password ? 1 : 0

  length  = 32
  special = true
  # RDS rejects these characters in a master password.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  count = local.self_managed_password ? 1 : 0

  name_prefix             = "${var.identifier}/master-"
  description             = "Master credentials for RDS PostgreSQL instance ${var.identifier}"
  kms_key_id              = var.master_user_secret_kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.tags, { Name = "${var.identifier}-master" })
}

resource "aws_secretsmanager_secret_version" "master" {
  count = local.self_managed_password ? 1 : 0

  secret_id = aws_secretsmanager_secret.master[0].id
  secret_string = jsonencode({
    username = var.username
    password = random_password.master[0].result
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = var.port
    dbname   = var.db_name
  })
}

################################################################################
# Enhanced monitoring role
################################################################################

data "aws_iam_policy_document" "monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${var.identifier}-rds-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role[0].json

  tags = merge(local.tags, { Name = "${var.identifier}-rds-monitoring" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# Instance
################################################################################

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name  = var.db_name
  username = var.username
  port     = var.port

  # Exactly one of these paths supplies the password.
  manage_master_user_password   = var.manage_master_user_password ? true : null
  master_user_secret_kms_key_id = var.manage_master_user_password ? var.master_user_secret_kms_key_arn : null
  password                      = local.self_managed_password ? random_password.master[0].result : null

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = var.publicly_accessible

  multi_az            = var.multi_az
  deletion_protection = var.deletion_protection

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = var.copy_tags_to_snapshot

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  apply_immediately           = var.apply_immediately
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = merge(local.tags, { Name = var.identifier })

  lifecycle {
    # The snapshot identifier embeds a timestamp, so it would otherwise force a
    # diff on every single plan.
    ignore_changes = [final_snapshot_identifier]
  }
}

################################################################################
# Secret rotation for the self-managed password
################################################################################

resource "aws_secretsmanager_secret_rotation" "master" {
  count = local.self_managed_password && var.password_rotation_days > 0 ? 1 : 0

  secret_id = aws_secretsmanager_secret.master[0].id

  rotation_rules {
    automatically_after_days = var.password_rotation_days
  }

  # Rotation needs a Lambda function wired up out of band; without one this
  # resource only records the schedule.
  lifecycle {
    ignore_changes = [rotation_lambda_arn]
  }

  depends_on = [aws_secretsmanager_secret_version.master]
}

################################################################################
# Baseline alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.identifier}-rds-cpu-high"
  alarm_description   = "CPU utilization on ${var.identifier} is above ${var.cpu_utilization_alarm_threshold}%."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_utilization_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.identifier}-rds-free-storage-low"
  alarm_description   = "Free storage on ${var.identifier} has dropped below the configured threshold."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.free_storage_alarm_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.identifier}-rds-connections-high"
  alarm_description   = "Database connection count on ${var.identifier} is unusually high."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.tags
}
