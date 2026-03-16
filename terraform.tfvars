# Kubeconfig path - adjust based on your setup
kubeconfig_path = "~/.kube/config"

# Namespace configuration
namespace            = "api-app-go"
create_namespace     = true
helm_release_name    = "api-observabilidade"
helm_chart_path      = "./helm-chart"

# Chart configuration
chart_version = "1.0.0"

# ========================================
# APPLICATION CONFIGURATION
# ========================================
inventory_app_image_tag  = "v4.0"
inventory_app_replicas   = 1
inventory_app_http_port  = 10000
inventory_app_metrics_port = 2113

# ========================================
# DATABASE CONFIGURATION
# ========================================
# IMPORTANTE: Senhas devem ser passadas via variáveis de ambiente:
#   export TF_VAR_mysql_root_password="sua_senha"
#   export TF_VAR_minio_root_password="sua_senha"
mysql_database      = "inventory"
mysql_storage_size  = "10Gi"
mysql_image_tag     = "8.0"

# ========================================
# INGRESS CONFIGURATION
# ========================================
ingress_enabled    = true
ingress_hostname   = "inventory.local"
ingress_class_name = "nginx"

# ========================================
# OBSERVABILITY STACK
# ========================================
grafana_enabled         = true
loki_enabled            = true
tempo_enabled           = true
mimir_enabled           = true
pyroscope_enabled       = true
alloy_enabled           = true
otel_collector_enabled  = true

# ========================================
# VAULT CONFIGURATION
# ========================================
vault_enabled     = true
vault_version     = "0.27.0"
vault_root_token  = "root"

# ========================================
# EXTERNAL SECRETS OPERATOR
# ========================================
eso_enabled  = true
eso_version  = "0.10.0"

# ========================================
# RESOURCE CONFIGURATION
# ========================================
resource_requests = {
  cpu    = "250m"
  memory = "64Mi"
}

resource_limits = {
  cpu    = "500m"
  memory = "128Mi"
}

# ========================================
# CUSTOM VALUES (Advanced)
# ========================================
# Para valores customizados, use um arquivo YAML
# helm_values_file = "./custom-values.yaml"
custom_values = {}
