# Install Vault
resource "helm_release" "vault" {
  count = var.vault_enabled ? 1 : 0

  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = var.vault_version
  namespace        = "vault"
  create_namespace = true
  wait             = true

  set {
    name  = "server.dev.enabled"
    value = "true"
  }

  set {
    name  = "server.dev.devRootToken"
    value = var.vault_root_token
  }
}

# Install External Secrets Operator
resource "helm_release" "external_secrets" {
  count = var.eso_enabled ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.eso_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true

  depends_on = [helm_release.vault]
}

# Initialize Vault: enable KV v2 and inject secrets
resource "null_resource" "vault_init" {
  count = var.vault_enabled ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Vault pod to be ready..."
      kubectl wait pod -n vault -l app.kubernetes.io/name=vault \
        --for=condition=Ready --timeout=120s

      echo "Enabling KV v2 secrets engine..."
      kubectl exec -n vault vault-0 -- \
        env VAULT_TOKEN=${var.vault_root_token} \
        vault secrets enable -path=secret kv-v2 2>/dev/null || \
        echo "KV v2 already enabled, skipping."

      echo "Injecting secrets into Vault..."
      kubectl exec -n vault vault-0 -- \
        env VAULT_TOKEN=${var.vault_root_token} \
        vault kv put secret/inventory \
          DB_PASSWORD=${var.mysql_root_password} \
          MYSQL_ROOT_PASSWORD=${var.mysql_root_password} \
          MINIO_ROOT_PASSWORD=${var.minio_root_password}

      echo "Vault init complete."
    EOT
  }

  depends_on = [helm_release.vault]
}

# Create Kubernetes secret with Vault root token for ESO authentication
resource "kubernetes_secret" "vault_token" {
  count = var.vault_enabled && var.eso_enabled ? 1 : 0

  metadata {
    name      = "vault-token"
    namespace = var.namespace
  }

  data = {
    token = var.vault_root_token
  }

  depends_on = [helm_release.external_secrets]
}


# Create ClusterSecretStore + ExternalSecrets via kubectl and wait for ESO to sync.
# Passwords never enter Terraform state — they flow: env var → Vault → ESO → K8s Secret.
resource "null_resource" "setup_external_secrets" {
  count = var.vault_enabled && var.eso_enabled ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      export NAMESPACE=${var.namespace}
      envsubst < ${path.module}/manifests/cluster-secret-store.yaml | kubectl apply -f -
      envsubst < ${path.module}/manifests/external-secrets.yaml | kubectl apply -f -

      echo "Waiting for ESO to sync secrets from Vault..."
      until kubectl get secret mysql-secrets -n ${var.namespace} >/dev/null 2>&1; do
        echo "  mysql-secrets not ready, retrying in 5s..."; sleep 5
      done
      until kubectl get secret inventory-app-secrets -n ${var.namespace} >/dev/null 2>&1; do
        echo "  inventory-app-secrets not ready, retrying in 5s..."; sleep 5
      done
      until kubectl get secret minio-secrets -n ${var.namespace} >/dev/null 2>&1; do
        echo "  minio-secrets not ready, retrying in 5s..."; sleep 5
      done
      echo "Secrets synced successfully."
    EOT
  }

  depends_on = [
    helm_release.external_secrets,
    null_resource.vault_init,
    kubernetes_secret.vault_token,
  ]
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

# Deploy Helm chart
resource "helm_release" "api_observabilidade" {
  name             = var.helm_release_name
  chart            = var.helm_chart_path
  namespace        = var.namespace
  create_namespace = true

  version = var.chart_version
  wait    = true
  timeout = 320

  # Convert local values to YAML and pass to Helm
  values = [
    yamlencode(local.helm_values)
  ]

  depends_on = [
    helm_release.external_secrets,
    null_resource.vault_init,
    kubernetes_secret.vault_token,
    null_resource.setup_external_secrets,
  ]
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