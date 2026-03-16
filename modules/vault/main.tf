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
