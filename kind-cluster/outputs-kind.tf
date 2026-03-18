# Outputs for Kind Cluster

output "kind_cluster_name" {
  description = "Kind cluster name"
  value       = var.kind_cluster_name
}

output "kind_cluster_context" {
  description = "Kubernetes context name for Kind cluster"
  value       = "kind-${var.kind_cluster_name}"
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = "kubectl config current-context"
}

output "cluster_info" {
  description = "Kind cluster information"
  value = {
    name        = var.kind_cluster_name
    context     = "kind-${var.kind_cluster_name}"
    k8s_version = var.kind_version
    addons = {
      cilium         = var.install_cilium
      metrics_server = var.install_metrics_server
      metallb        = var.install_metallb
      ingress_nginx  = var.install_ingress_nginx
    }
  }
}

output "useful_commands" {
  description = "Useful kubectl commands"
  value = {
    get_nodes           = "kubectl get nodes --context=kind-${var.kind_cluster_name}"
    get_pods_all        = "kubectl get pods -A --context=kind-${var.kind_cluster_name}"
    get_ingress         = "kubectl get ingress -A --context=kind-${var.kind_cluster_name}"
    describe_cluster    = "kubectl cluster-info --context=kind-${var.kind_cluster_name}"
    delete_cluster      = "kind delete cluster --name=${var.kind_cluster_name}"
  }
}

output "metallb_pool_info" {
  description = "MetalLB pool information"
  value = var.install_metallb ? "Run: kubectl get ipaddresspools -n metallb-system" : "MetalLB not installed"
}

output "ingress_nginx_info" {
  description = "Nginx Ingress Controller information"
  value = var.install_ingress_nginx ? {
    command       = "kubectl get svc -n kube-system | grep ingress-nginx"
    port_forward  = "kubectl port-forward -n kube-system svc/ingress-nginx-controller 80:80 443:443"
  } : {}
}


