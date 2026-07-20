output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "default_security_group_id" {
  description = "ID of the security group created by default with the VPC."
  value       = aws_vpc.this.default_security_group_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "ARNs of the public subnets."
  value       = aws_subnet.public[*].arn
}

output "public_subnet_cidr_blocks" {
  description = "CIDR blocks of the public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "ARNs of the private subnets."
  value       = aws_subnet.private[*].arn
}

output "private_subnet_cidr_blocks" {
  description = "CIDR blocks of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "intra_subnet_ids" {
  description = "IDs of the intra (fully isolated) subnets."
  value       = aws_subnet.intra[*].id
}

output "intra_subnet_arns" {
  description = "ARNs of the intra subnets."
  value       = aws_subnet.intra[*].arn
}

output "intra_subnet_cidr_blocks" {
  description = "CIDR blocks of the intra subnets."
  value       = aws_subnet.intra[*].cidr_block
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when no public subnets were requested."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Elastic IP addresses in front of the NAT gateways. Useful for allow-listing egress with third parties."
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_ids" {
  description = "IDs of the public route tables."
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables."
  value       = aws_route_table.private[*].id
}

output "intra_route_table_ids" {
  description = "IDs of the intra route tables."
  value       = aws_route_table.intra[*].id
}

output "azs" {
  description = "Availability Zones the subnets were spread across."
  value       = var.azs
}

output "flow_log_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Logs group receiving flow logs, or null when flow logs are disabled."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
