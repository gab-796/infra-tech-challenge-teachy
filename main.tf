# Create namespace
resource "kubernetes_namespace" "api_app" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }

  depends_on = []
}

# Local values for Helm charts
locals {
  helm_values = merge(
    yamldecode(var.helm_values_file != "" ? file(var.helm_values_file) : "{}"),
    {
      global = {
        namespace        = var.namespace
        imagePullPolicy  = "IfNotPresent"
        storageClass     = "standard"
      }
      
      inventoryApp = {
        enabled     = true
        replicaCount = var.inventory_app_replicas
        image = {
          tag = var.inventory_app_image_tag
        }
        ports = {
          http    = var.inventory_app_http_port
          metrics = var.inventory_app_metrics_port
        }
      }
      
      mysql = {
        enabled = true
        image = {
          tag = var.mysql_image_tag
        }
        config = {
          rootPassword = var.mysql_root_password
          database     = var.mysql_database
        }
        persistence = {
          size = var.mysql_storage_size
        }
      }
      
      grafana = {
        enabled = var.grafana_enabled
      }
      
      loki = {
        enabled = var.loki_enabled
      }
      
      tempo = {
        enabled = var.tempo_enabled
      }
      
      mimir = {
        enabled = var.mimir_enabled
      }
      
      pyroscope = {
        enabled = var.pyroscope_enabled
      }
      
      alloy = {
        enabled = var.alloy_enabled
      }
      
      otelCollector = {
        enabled = var.otel_collector_enabled
      }
    },
    var.custom_values
  )
}

# Deploy Helm chart
resource "helm_release" "api_observabilidade" {
  name      = var.helm_release_name
  chart     = var.helm_chart_path
  namespace = var.namespace
  
  version = var.chart_version
  wait    = true

  # Convert local values to YAML and pass to Helm
  values = [
    yamlencode(local.helm_values)
  ]

  depends_on = [
    kubernetes_namespace.api_app
  ]

  # Set individual values (overrides values from file)
  set_sensitive {
    name  = "mysql.config.rootPassword"
    value = var.mysql_root_password
  }
}
