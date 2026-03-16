# Namespace criado no root para que tanto external_secrets quanto app possam depender dele
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace
  }
}

module "vault" {
  source = "./modules/vault"

  vault_enabled       = var.vault_enabled
  vault_version       = var.vault_version
  vault_root_token    = var.vault_root_token
  mysql_root_password = var.mysql_root_password
  minio_root_password = var.minio_root_password
}

module "external_secrets" {
  source = "./modules/external-secrets"

  vault_enabled    = var.vault_enabled
  eso_enabled      = var.eso_enabled
  eso_version      = var.eso_version
  namespace        = var.namespace
  vault_root_token = var.vault_root_token

  depends_on = [module.vault, kubernetes_namespace.app_namespace]
}

module "app" {
  source = "./modules/app"

  namespace                  = var.namespace
  helm_release_name          = var.helm_release_name
  helm_chart_path            = var.helm_chart_path
  helm_values_file           = var.helm_values_file
  chart_version              = var.chart_version
  inventory_app_replicas     = var.inventory_app_replicas
  inventory_app_image_tag    = var.inventory_app_image_tag
  inventory_app_http_port    = var.inventory_app_http_port
  inventory_app_metrics_port = var.inventory_app_metrics_port
  mysql_image_tag            = var.mysql_image_tag
  mysql_database             = var.mysql_database
  mysql_storage_size         = var.mysql_storage_size
  grafana_enabled            = var.grafana_enabled
  loki_enabled               = var.loki_enabled
  tempo_enabled              = var.tempo_enabled
  mimir_enabled              = var.mimir_enabled
  pyroscope_enabled          = var.pyroscope_enabled
  alloy_enabled              = var.alloy_enabled
  otel_collector_enabled     = var.otel_collector_enabled
  custom_values              = var.custom_values

  depends_on = [module.external_secrets]
}
