# VPC

A multi-AZ VPC with up to three subnet tiers, optional NAT gateways and flow logs.

## Subnet tiers

| Tier | Internet inbound | Internet outbound | Typical use |
| --- | --- | --- | --- |
| `public` | Yes, via IGW | Yes, via IGW | Load balancers, NAT gateways, bastions |
| `private` | No | Yes, via NAT | EKS nodes, ECS tasks, EC2 app servers |
| `intra` | No | **No route at all** | RDS, ElastiCache, VPC endpoints |

Intra subnets are the important one. They get a route table with no default
route, so a workload placed there cannot reach the internet even if a security
group is misconfigured. Put your databases here.

Each private subnet gets its own route table, so with `single_nat_gateway = false`
traffic from an AZ egresses through the NAT gateway in that same AZ — no
cross-AZ data transfer charges, and one NAT failure does not take out the
whole VPC.

## Usage

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
  single_nat_gateway = false # one per AZ in production

  enable_flow_logs            = true
  flow_logs_retention_in_days = 90

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

### Tagging subnets for EKS

The AWS Load Balancer Controller discovers subnets by tag. When this VPC hosts
an EKS cluster:

```hcl
public_subnet_tags = {
  "kubernetes.io/role/elb"                  = "1"
  "kubernetes.io/cluster/my-cluster"        = "shared"
}

private_subnet_tags = {
  "kubernetes.io/role/internal-elb"         = "1"
  "kubernetes.io/cluster/my-cluster"        = "shared"
}
```

## Cost note

NAT gateways are the single largest line item in a small VPC — roughly $32/month
each plus data processing charges. `single_nat_gateway = true` collapses three
into one, which is the right call for dev and staging and the wrong call for
production.

## Notes

- The number of entries in `public_subnets`, `private_subnets` and
  `intra_subnets` should match the length of `azs`; index `n` of each list lands
  in AZ `n`.
- NAT gateways are only created when there is at least one public subnet
  (somewhere to put them) and at least one private subnet (something that needs
  them). Setting `enable_nat_gateway = true` with no private subnets is a no-op.
- Flow logs go to CloudWatch Logs with a dedicated IAM role. Set
  `flow_logs_kms_key_arn` to encrypt the log group with a customer-managed key.
- `map_public_ip_on_launch` defaults to `false`. Turn it on only if you are
  launching instances directly into public subnets and want them addressable.

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
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_iam_policy_document.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_azs"></a> [azs](#input\_azs) | Availability Zones to spread subnets across. Provide at least two for a highly available deployment. | `list(string)` | n/a | yes |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | IPv4 CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Enable DNS hostnames in the VPC. Required by EKS and RDS private endpoints. | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Enable DNS resolution in the VPC. | `bool` | `true` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC flow logs delivered to CloudWatch Logs. | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Provision NAT gateways so private subnets get outbound internet access. Requires at least one public subnet. | `bool` | `true` | no |
| <a name="input_flow_logs_kms_key_arn"></a> [flow\_logs\_kms\_key\_arn](#input\_flow\_logs\_kms\_key\_arn) | KMS key ARN used to encrypt the flow log group. Defaults to AWS-managed CloudWatch Logs encryption when null. | `string` | `null` | no |
| <a name="input_flow_logs_retention_in_days"></a> [flow\_logs\_retention\_in\_days](#input\_flow\_logs\_retention\_in\_days) | Retention period for the flow log CloudWatch Logs group. | `number` | `90` | no |
| <a name="input_flow_logs_traffic_type"></a> [flow\_logs\_traffic\_type](#input\_flow\_logs\_traffic\_type) | Which traffic to capture in flow logs: ACCEPT, REJECT or ALL. | `string` | `"ALL"` | no |
| <a name="input_intra_subnet_tags"></a> [intra\_subnet\_tags](#input\_intra\_subnet\_tags) | Additional tags applied only to intra subnets. | `map(string)` | `{}` | no |
| <a name="input_intra_subnets"></a> [intra\_subnets](#input\_intra\_subnets) | CIDR blocks for intra subnets. Intra subnets have no route to the internet at all and are intended for databases and internal endpoints. | `list(string)` | `[]` | no |
| <a name="input_map_public_ip_on_launch"></a> [map\_public\_ip\_on\_launch](#input\_map\_public\_ip\_on\_launch) | Automatically assign a public IP to instances launched in public subnets. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix applied to the VPC and all subordinate resources. | `string` | n/a | yes |
| <a name="input_private_subnet_tags"></a> [private\_subnet\_tags](#input\_private\_subnet\_tags) | Additional tags applied only to private subnets. Commonly used for `kubernetes.io/role/internal-elb`. | `map(string)` | `{}` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | CIDR blocks for the private (egress via NAT) subnets. Index order must line up with `azs`. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_tags"></a> [public\_subnet\_tags](#input\_public\_subnet\_tags) | Additional tags applied only to public subnets. Commonly used for `kubernetes.io/role/elb`. | `map(string)` | `{}` | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | CIDR blocks for the public subnets. Index order must line up with `azs`. Leave empty to skip public subnets (and the internet gateway). | `list(string)` | `[]` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Deploy a single shared NAT gateway instead of one per AZ. Cheaper, but the NAT becomes a single point of failure and a cross-AZ data transfer cost. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_azs"></a> [azs](#output\_azs) | Availability Zones the subnets were spread across. |
| <a name="output_default_security_group_id"></a> [default\_security\_group\_id](#output\_default\_security\_group\_id) | ID of the security group created by default with the VPC. |
| <a name="output_flow_log_cloudwatch_log_group_name"></a> [flow\_log\_cloudwatch\_log\_group\_name](#output\_flow\_log\_cloudwatch\_log\_group\_name) | Name of the CloudWatch Logs group receiving flow logs, or null when flow logs are disabled. |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | ID of the internet gateway, or null when no public subnets were requested. |
| <a name="output_intra_route_table_ids"></a> [intra\_route\_table\_ids](#output\_intra\_route\_table\_ids) | IDs of the intra route tables. |
| <a name="output_intra_subnet_arns"></a> [intra\_subnet\_arns](#output\_intra\_subnet\_arns) | ARNs of the intra subnets. |
| <a name="output_intra_subnet_cidr_blocks"></a> [intra\_subnet\_cidr\_blocks](#output\_intra\_subnet\_cidr\_blocks) | CIDR blocks of the intra subnets. |
| <a name="output_intra_subnet_ids"></a> [intra\_subnet\_ids](#output\_intra\_subnet\_ids) | IDs of the intra (fully isolated) subnets. |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | IDs of the NAT gateways. |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Elastic IP addresses in front of the NAT gateways. Useful for allow-listing egress with third parties. |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | IDs of the private route tables. |
| <a name="output_private_subnet_arns"></a> [private\_subnet\_arns](#output\_private\_subnet\_arns) | ARNs of the private subnets. |
| <a name="output_private_subnet_cidr_blocks"></a> [private\_subnet\_cidr\_blocks](#output\_private\_subnet\_cidr\_blocks) | CIDR blocks of the private subnets. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | IDs of the private subnets. |
| <a name="output_public_route_table_ids"></a> [public\_route\_table\_ids](#output\_public\_route\_table\_ids) | IDs of the public route tables. |
| <a name="output_public_subnet_arns"></a> [public\_subnet\_arns](#output\_public\_subnet\_arns) | ARNs of the public subnets. |
| <a name="output_public_subnet_cidr_blocks"></a> [public\_subnet\_cidr\_blocks](#output\_public\_subnet\_cidr\_blocks) | CIDR blocks of the public subnets. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | IDs of the public subnets. |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | ARN of the VPC. |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | CIDR block of the VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
<!-- END_TF_DOCS -->
