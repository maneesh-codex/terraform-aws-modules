output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs hosting the worker nodes."
  value       = module.vpc.private_subnet_ids
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN, for wiring up further IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Shared worker node security group ID."
  value       = module.eks.node_security_group_id
}

output "kubeconfig_command" {
  description = "Command to configure kubectl against this cluster."
  value       = module.eks.kubeconfig_command
}

output "artifacts_bucket_id" {
  description = "Name of the artifacts bucket."
  value       = module.artifacts_bucket.bucket_id
}

output "irsa_role_arns" {
  description = "IRSA role ARNs, keyed by purpose. Annotate the matching service accounts with these."
  value = {
    ebs_csi                  = module.ebs_csi_irsa.iam_role_arn
    load_balancer_controller = module.load_balancer_controller_irsa.iam_role_arn
    cluster_autoscaler       = module.cluster_autoscaler_irsa.iam_role_arn
    app                      = module.app_irsa.iam_role_arn
  }
}
