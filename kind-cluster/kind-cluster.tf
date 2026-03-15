# Kind Cluster Terraform Resources

# Local script to create Kind cluster
resource "null_resource" "kind_cluster_create" {
  count = var.create_kind_cluster ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Check if cluster already exists
      if kind get clusters -q 2>/dev/null | grep -q "^${var.kind_cluster_name}$"; then
        echo "Cluster ${var.kind_cluster_name} already exists"
        exit 0
      fi
      
      echo "Creating Kind cluster: ${var.kind_cluster_name}"
      
      # Ensure docker kind network exists
      docker network inspect kind >/dev/null 2>&1 || docker network create kind
      
      # Create cluster
      kind create cluster --name ${var.kind_cluster_name} --config=${var.kind_config_path} --wait 10s
      
      echo "Kind cluster created successfully!"
    EOT

    interpreter = ["bash", "-c"]
    working_dir = path.module
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      echo "Deleting Kind cluster: ${self.triggers.cluster_name}"
      kind delete cluster --name ${self.triggers.cluster_name} || true
      echo "Kind cluster deleted!"
    EOT

    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.kind_cluster_name
    config_file  = filemd5("${path.module}/${var.kind_config_path}")
  }
}

# Tune inotify settings
resource "null_resource" "inotify_tuning" {
  count = var.enable_inotify_tuning ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Tuning inotify settings..."
      
      # Check if running with sudo capability
      if sudo -n true 2>/dev/null; then
        sudo sysctl fs.inotify.max_user_watches=524288
        sudo sysctl fs.inotify.max_user_instances=512
        echo "inotify tuning completed"
      else
        echo "Warning: Cannot apply inotify tuning without sudo. Please run manually:"
        echo "  sudo sysctl fs.inotify.max_user_watches=524288"
        echo "  sudo sysctl fs.inotify.max_user_instances=512"
      fi
    EOT
    
    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.kind_cluster_create]
}

# Helm repository for Cilium
# Install Cilium CNI
resource "helm_release" "cilium" {
  count = var.install_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  depends_on = [null_resource.kind_cluster_create]
}

# Install Metrics Server
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [helm_release.cilium]
}

# Install MetalLB
resource "null_resource" "metallb_install" {
  count = var.install_metallb ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Installing MetalLB..."
      
      # Apply MetalLB manifests
      kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v${var.metallb_version}/config/manifests/metallb-native.yaml
      
      # Wait for controller to be ready
      kubectl rollout status -n metallb-system deployment controller
      
      # Get docker subnet and configure MetalLB
      DOCKER_SUBNET=$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' kind)
      
      echo "Configuring MetalLB with subnet: $DOCKER_SUBNET"
      
      # Create IPAddressPool and L2Advertisement
      cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: metallb-pool
  namespace: metallb-system
spec:
  addresses:
  - $DOCKER_SUBNET
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
      
      echo "MetalLB installed successfully!"
    EOT
    
    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.kind_cluster_name
  }

  depends_on = [helm_release.metrics_server]
}

# Helm repository for Nginx Ingress
# Install Nginx Ingress Controller
resource "helm_release" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = "kube-system"

  depends_on = [null_resource.metallb_install]
}

# Wait for cluster to be ready
resource "null_resource" "cluster_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Waiting for cluster to be fully ready..."
      
      # Wait for control plane
      kubectl wait --for=condition=Ready node --all --timeout=300s --context=kind-${var.kind_cluster_name} || true
      
      echo "Cluster is ready!"
    EOT
    
    interpreter = ["bash", "-c"]
  }

  depends_on = [helm_release.ingress_nginx]
}
