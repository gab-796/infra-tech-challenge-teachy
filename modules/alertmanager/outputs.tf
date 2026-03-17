output "alertmanager_url" {
  description = "AlertManager internal cluster URL for Mimir ruler alertmanager_url config"
  value       = var.alertmanager_enabled ? "http://alertmanager.${var.alertmanager_namespace}.svc.cluster.local:9093" : ""
}

output "mailhog_smtp_endpoint" {
  description = "MailHog internal SMTP endpoint used by AlertManager (same namespace, short name works)"
  value       = var.alertmanager_enabled ? "mailhog.${var.alertmanager_namespace}.svc.cluster.local:1025" : ""
}
