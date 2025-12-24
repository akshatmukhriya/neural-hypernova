variable "target" {
  description = "Target environment: 'local' or 'aws'"
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "aws"], var.target)
    error_message = "Target must be 'local' or 'aws'."
  }
}

# --- MODULE 1: LOCAL (MINIKUBE) ---
module "local" {
  source = "./modules/local"
  # Only create this if target is local
  count  = var.target == "local" ? 1 : 0
}

# --- MODULE 2: CLOUD (AWS EKS) ---
module "aws" {
  source = "./modules/aws"
  # Only create this if target is aws
  count  = var.target == "aws" ? 1 : 0
}

# --- THE BRIDGE: INVENTORY GENERATION ---
resource "local_file" "ansible_inventory" {
  # Logic: Check target, grab kubeconfig from the active module [index 0]
  content = <<EOF
[supernova]
localhost ansible_connection=local

[supernova:vars]
kubeconfig_path=${var.target == "local" ? module.local[0].kubeconfig_path : module.aws[0].kubeconfig_path}
target_env=${var.target}
EOF
  filename = "${path.module}/inventory.ini"
}