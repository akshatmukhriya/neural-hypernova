output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region"
  value       = "us-east-1" # Or use your var.region
}

output "karpenter_node_role_arn" {
  description = "The ARN of the IAM role for Karpenter nodes"
  value       = module.eks.eks_managed_node_groups["brain"].iam_role_arn
}