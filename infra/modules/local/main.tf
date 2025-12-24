resource "null_resource" "minikube_start" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      # [SAME AUTO-HEAL LOGIC AS BEFORE - KEEP IT]
      echo ">> [PRE-FLIGHT] Checking Docker Daemon status..."
      if ! docker info > /dev/null 2>&1; then
        echo "❌ [ERROR] Docker is NOT running."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "   [AUTO-FIX] Attempting to start Docker.app..."
            open -a Docker
            for i in {1..15}; do
                if docker info > /dev/null 2>&1; then echo "✅ Docker started."; break; fi
                sleep 2
            done
        fi
      fi
      
      # 2. IGNITION - TUNED FOR LOCAL DEV
      # Reduced Memory to 6000MB to fit inside standard Docker Desktop limits
      echo ">> [IGNITION] Starting Minikube Cluster..."
      minikube start --cpus 4 --memory 6000 --driver docker
    EOT
  }

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

output "kubeconfig_path" {
  value = "~/.kube/config"
}