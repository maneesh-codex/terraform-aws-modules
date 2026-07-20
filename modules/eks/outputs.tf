output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "EKS platform version of the cluster."
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster. Feed this to the kubernetes/helm providers or kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the security group attached to the control plane ENIs."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "ID of the shared worker node security group. Reference this from RDS or other backing services to allow pod traffic."
  value       = aws_security_group.node.id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider. Pass this into the iam-irsa-role module."
  value       = try(aws_iam_openid_connect_provider.this[0].arn, null)
}

output "node_group_arns" {
  description = "ARNs of the managed node groups, keyed by node group name."
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_group_iam_role_arns" {
  description = "IAM role ARNs of the managed node groups, keyed by node group name."
  value       = { for k, v in aws_iam_role.node : k => v.arn }
}

output "node_group_autoscaling_group_names" {
  description = "Autoscaling group names backing each managed node group."
  value = {
    for k, v in aws_eks_node_group.this :
    k => try(v.resources[0].autoscaling_groups[*].name, [])
  }
}

output "cluster_addon_versions" {
  description = "Resolved versions of the installed EKS addons, keyed by addon name."
  value       = { for k, v in aws_eks_addon.this : k => v.addon_version }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secret envelope encryption, or null when disabled."
  value       = local.kms_key_arn
}

output "kubeconfig_command" {
  description = "Convenience command to write a kubeconfig entry for this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.name}"
}
