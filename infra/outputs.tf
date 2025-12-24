output "kubeconfig_path" {
  description = "Path to the generated Kubeconfig"
  value       = var.target == "local" ? module.local[0].kubeconfig_path : module.aws[0].kubeconfig_path
}

output "cluster_status" {
  value = "Active in ${var.target} mode"
}