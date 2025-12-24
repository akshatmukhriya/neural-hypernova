resource "null_resource" "minikube" {
  provisioner "local-exec" {
    command = "minikube start --cpus 4 --memory 8192 --driver docker"
  }
}
output "kubeconfig_path" { value = "~/.kube/config" }