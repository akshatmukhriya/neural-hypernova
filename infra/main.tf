variable "target" { default = "local" }

# 1. Decide: Local or AWS?
module "cluster" {
  source = "./modules/${var.target}" # Dynamic loading
}

# 2. The Bridge: Write Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = <<EOF
[supernova]
localhost ansible_connection=local

[supernova:vars]
kubeconfig_path=${module.cluster.kubeconfig_path}
EOF
  filename = "${path.module}/inventory.ini"
}