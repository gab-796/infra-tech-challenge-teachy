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
    kubernetes_secret.vault_token,
  ]
}
