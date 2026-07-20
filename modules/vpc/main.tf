locals {
  tags = merge(var.tags, { "terraform-module" = "vpc" })

  public_subnet_count  = length(var.public_subnets)
  private_subnet_count = length(var.private_subnets)
  intra_subnet_count   = length(var.intra_subnets)

  create_igw = local.public_subnet_count > 0

  # NAT gateways only make sense when we have both a public subnet to place them
  # in and a private subnet that needs egress.
  create_nat = var.enable_nat_gateway && local.public_subnet_count > 0 && local.private_subnet_count > 0

  nat_gateway_count = local.create_nat ? (var.single_nat_gateway ? 1 : local.public_subnet_count) : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.tags, { Name = var.name })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = local.create_igw ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = var.name })
}

################################################################################
# Public subnets
################################################################################

resource "aws_subnet" "public" {
  count = local.public_subnet_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    local.tags,
    var.public_subnet_tags,
    { Name = "${var.name}-public-${element(var.azs, count.index)}" },
  )
}

resource "aws_route_table" "public" {
  count = local.public_subnet_count > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet_gateway" {
  count = local.create_igw ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "public" {
  count = local.public_subnet_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

################################################################################
# NAT gateways
################################################################################

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-${element(var.azs, count.index)}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${var.name}-nat-${element(var.azs, count.index)}" })

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Private subnets
################################################################################

resource "aws_subnet" "private" {
  count = local.private_subnet_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    local.tags,
    var.private_subnet_tags,
    { Name = "${var.name}-private-${element(var.azs, count.index)}" },
  )
}

# One route table per private subnet so each AZ can point at its own NAT gateway.
resource "aws_route_table" "private" {
  count = local.private_subnet_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-private-${element(var.azs, count.index)}" })
}

resource "aws_route" "private_nat_gateway" {
  count = local.create_nat ? local.private_subnet_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, var.single_nat_gateway ? 0 : count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "private" {
  count = local.private_subnet_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

################################################################################
# Intra subnets - deliberately isolated, no route off the VPC
################################################################################

resource "aws_subnet" "intra" {
  count = local.intra_subnet_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.intra_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    local.tags,
    var.intra_subnet_tags,
    { Name = "${var.name}-intra-${element(var.azs, count.index)}" },
  )
}

resource "aws_route_table" "intra" {
  count = local.intra_subnet_count > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-intra" })
}

resource "aws_route_table_association" "intra" {
  count = local.intra_subnet_count

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra[0].id
}

################################################################################
# Flow logs
################################################################################

data "aws_iam_policy_document" "flow_logs_assume_role" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.name}"
  retention_in_days = var.flow_logs_retention_in_days
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = merge(local.tags, { Name = "${var.name}-flow-logs" })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix        = "${var.name}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role[0].json

  tags = merge(local.tags, { Name = "${var.name}-flow-logs" })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name}-flow-logs-"
  role        = aws_iam_role.flow_logs[0].id
  policy      = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 600

  tags = merge(local.tags, { Name = "${var.name}-flow-logs" })
}
