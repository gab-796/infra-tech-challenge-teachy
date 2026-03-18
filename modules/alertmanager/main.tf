# MailHog — fake SMTP server used as AlertManager receiver for local testing
resource "helm_release" "mailhog" {
  count = var.alertmanager_enabled ? 1 : 0

  name             = "mailhog"
  repository       = "https://codecentric.github.io/helm-charts"
  chart            = "mailhog"
  version          = var.mailhog_version
  namespace        = var.alertmanager_namespace
  create_namespace = true
  wait             = true
  timeout          = 120

  values = [yamlencode({
    image = {
      repository = "mailhog/mailhog"
      tag        = "v1.0.1"
      pullPolicy = "IfNotPresent"
    }

    service = {
      type = "ClusterIP"
      port = {
        http = 8025
      }
    }

    ingress = {
      enabled          = true
      ingressClassName = "nginx"
      hosts = [
        {
          host = "mailhog.local"
          paths = [
            {
              path     = "/"
              pathType = "Prefix"
            }
          ]
        }
      ]
    }

    resources = {
      limits   = { memory = "128Mi", cpu = "100m" }
      requests = { memory = "64Mi", cpu = "50m" }
    }
  })]
}

# AlertManager — receives alerts from Mimir ruler and routes to MailHog via SMTP
resource "helm_release" "alertmanager" {
  count = var.alertmanager_enabled ? 1 : 0

  name             = "alertmanager"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "alertmanager"
  version          = var.alertmanager_version
  namespace        = var.alertmanager_namespace
  create_namespace = false
  wait             = true
  timeout          = 180

  values = [yamlencode({
    replicaCount = 1

    image = {
      repository = "quay.io/prometheus/alertmanager"
      tag        = "v0.30.1"
      pullPolicy = "IfNotPresent"
    }

    config = {
      global = {
        smtp_smarthost   = "mailhog:1025"
        smtp_from        = "alertmanager@observability.local"
        smtp_require_tls = false
      }
      route = {
        group_by        = ["alertname", "namespace"]
        group_wait      = "30s"
        group_interval  = "5m"
        repeat_interval = "1h"
        receiver        = "email-mailhog"
      }
      receivers = [
        {
          name = "email-mailhog"
          email_configs = [
            {
              to            = "alerts@observability.local"
              send_resolved = true
            }
          ]
        }
      ]
      inhibit_rules = []
    }

    ingress = {
      enabled   = true
      ingressClassName = "nginx"
      hosts = [
        {
          host = "alertmanager.local"
          paths = [
            {
              path     = "/"
              pathType = "Prefix"
            }
          ]
        }
      ]
    }

    persistence = {
      enabled = false
    }

    resources = {
      limits   = { memory = "128Mi", cpu = "200m" }
      requests = { memory = "64Mi", cpu = "50m" }
    }
  })]

  depends_on = [helm_release.mailhog]
}
