# infra/modules/local/main.tf

resource "null_resource" "minikube_start" {
  # This acts as a trigger to start Minikube
  provisioner "local-exec" {
    command = "minikube status || minikube start --cpus 4 --memory 8192 --driver docker"
  }

  # This cleans up when you destroy
  provisioner "local-exec" {
    when    = destroy
    command = "minikube delete"
  }
}

resource "null_resource" "kubeconfig_check" {
  depends_on = [null_resource.minikube_start]
  provisioner "local-exec" {
    command = "minikube update-context"
  }
}

# IMPORTANT: We must output the path for the inventory file
output "kubeconfig_path" {
  value = "~/.kube/config"
}