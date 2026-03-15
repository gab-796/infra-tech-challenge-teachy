output "helm_release_id" {
  description = "Helm release ID"
  value       = helm_release.api_observabilidade.id
}

output "helm_release_name" {
  description = "Helm release name"
  value       = helm_release.api_observabilidade.name
}

output "helm_release_namespace" {
  description = "Helm release namespace"
  value       = helm_release.api_observabilidade.namespace
}

output "helm_release_status" {
  description = "Helm release status"
  value       = helm_release.api_observabilidade.status
}

output "namespace_name" {
  description = "Kubernetes namespace name"
  value       = var.namespace
}

output "ingress_hostname" {
  description = "Ingress hostname for accessing the app"
  value       = var.ingress_hostname
}

output "app_http_ports" {
  description = "Application service ports"
  value = {
    http    = var.inventory_app_http_port
    metrics = var.inventory_app_metrics_port
  }
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    release_name     = helm_release.api_observabilidade.name
    namespace        = helm_release.api_observabilidade.namespace
    chart            = helm_release.api_observabilidade.chart
    status           = helm_release.api_observabilidade.status
    app_replicas     = var.inventory_app_replicas
    mysql_database   = var.mysql_database
  }
}

# Useful kubectl commands for users
output "kubectl_commands" {
  description = "Useful kubectl commands"
  sensitive   = true
  value = {
    get_pods           = "kubectl get pods -n ${var.namespace}"
    get_services       = "kubectl get services -n ${var.namespace}"
    get_ingress        = "kubectl get ingress -n ${var.namespace}"
    check_helm_release = "helm list -n ${var.namespace}"
    view_logs_app      = "kubectl logs -n ${var.namespace} deployment/inventory-app"
    view_logs_mysql    = "kubectl logs -n ${var.namespace} deployment/mysql"
    port_forward_app   = "kubectl port-forward -n ${var.namespace} deployment/inventory-app 10000:${var.inventory_app_http_port}"
    port_forward_mysql = "kubectl port-forward -n ${var.namespace} deployment/mysql 3306:3306"
    exec_mysql         = "kubectl exec -it -n ${var.namespace} deployment/mysql -- mysql -u root -p${var.mysql_root_password}"
  }
}
