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

output "helm_release_chart" {
  description = "Helm chart used"
  value       = helm_release.api_observabilidade.chart
}

output "namespace_name" {
  description = "Application namespace name"
  value       = var.namespace
}
