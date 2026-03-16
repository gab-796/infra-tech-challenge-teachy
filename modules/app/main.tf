# Local values for Helm chart
locals {
  helm_values = merge(
    yamldecode(var.helm_values_file != "" ? file(var.helm_values_file) : "{}"),
    {
      global = {
        namespace       = var.namespace
        imagePullPolicy = "IfNotPresent"
        storageClass    = "standard"
      }

      inventoryApp = {
        enabled      = true
        replicaCount = var.inventory_app_replicas
        image = {
          tag = var.inventory_app_image_tag
        }
        ports = {
          http    = var.inventory_app_http_port
          metrics = var.inventory_app_metrics_port
        }
        externalSecret = {
          enabled = false
        }
      }

      mysql = {
        enabled = true
        image = {
          tag = var.mysql_image_tag
        }
        config = {
          database = var.mysql_database
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

# Deploy main Helm chart
resource "helm_release" "api_observabilidade" {
  name             = var.helm_release_name
  chart            = var.helm_chart_path
  namespace        = var.namespace
  create_namespace = false
  version          = var.chart_version
  wait             = true
  timeout          = 320

  values = [yamlencode(local.helm_values)]
}

# Install kube-state-metrics
resource "helm_release" "ksm" {
  name             = "ksm"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-state-metrics"
  version          = "7.1.0"
  namespace        = "ksm"
  create_namespace = true
  wait             = true

  set {
    name  = "image.tag"
    value = "v2.18.0"
  }

  depends_on = [helm_release.api_observabilidade]
}
