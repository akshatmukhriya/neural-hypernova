resource "null_resource" "minikube_start" {
  # Trigger only if specs change
  triggers = {
    always_run = "${timestamp()}" # Force check every time
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      echo ">> [PRE-FLIGHT] Checking Docker Daemon status..."
      
      # 1. Check if Docker CLI responds
      if ! docker info > /dev/null 2>&1; then
        echo "❌ [ERROR] Docker is NOT running."
        echo "   Action Required: Start Docker Desktop on your machine."
        
        # MAC OS AUTOMATION (Attempt to auto-start if on Mac)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "   [AUTO-FIX] Attempting to start Docker.app..."
            open -a Docker
            echo "   Waiting for Docker to initialize (this may take 30s)..."
            
            # Wait loop
            for i in {1..15}; do
                if docker info > /dev/null 2>&1; then
                    echo "✅ Docker started successfully."
                    break
                fi
                echo -n "."
                sleep 2
            done
            
            # Final check
            if ! docker info > /dev/null 2>&1; then
                 echo "❌ Failed to start Docker. Please start it manually and retry."
                 exit 1
            fi
        else
            exit 1
        fi
      else
        echo "✅ [PRE-FLIGHT] Docker is ready."
      fi

      # 2. Ignite Minikube
      echo ">> [IGNITION] Starting Minikube Cluster..."
      minikube status || minikube start --cpus 4 --memory 8192 --driver docker
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