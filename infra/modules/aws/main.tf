# infra/modules/aws/main.tf

# Placeholder resources so the module is valid
resource "null_resource" "aws_placeholder" {
  provisioner "local-exec" {
    command = "echo 'AWS Module Loaded (Inactive)'"
  }
}

# We need matching outputs to avoid errors in the main root module
output "kubeconfig_path" {
  value = "generated_kubeconfig.yaml" 
}