variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use (optional)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace where the application will be deployed"
  type        = string
  default     = "api-app-go"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "api-observabilidade"
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
  default     = "../helm-chart/infra-tech-challenge-teachy"
}

variable "helm_values_file" {
  description = "Path to custom values file (optional)"
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Version of the chart to deploy"
  type        = string
  default     = "1.0.0"
}

# ========================================
# APPLICATION CONFIGURATION
# ========================================
variable "inventory_app_image_tag" {
  description = "Docker image tag for inventory app"
  type        = string
  default     = "v4.0"
}

variable "inventory_app_replicas" {
  description = "Number of replicas for inventory app"
  type        = number
  default     = 1
}

variable "inventory_app_http_port" {
  description = "HTTP port for inventory app"
  type        = number
  default     = 10000
}

variable "inventory_app_metrics_port" {
  description = "Metrics port for inventory app"
  type        = number
  default     = 2113
}

# ========================================
# DATABASE CONFIGURATION
# ========================================
variable "mysql_image_tag" {
  description = "MySQL image tag"
  type        = string
  default     = "8.0"
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
  default     = "rootpassword"
}

variable "mysql_database" {
  description = "MySQL database name"
  type        = string
  default     = "inventory"
}

variable "mysql_storage_size" {
  description = "MySQL persistent volume size"
  type        = string
  default     = "10Gi"
}

# ========================================
# INGRESS CONFIGURATION
# ========================================
variable "ingress_enabled" {
  description = "Enable Ingress"
  type        = bool
  default     = true
}

variable "ingress_hostname" {
  description = "Ingress hostname"
  type        = string
  default     = "inventory.local"
}

variable "ingress_class_name" {
  description = "Ingress class name"
  type        = string
  default     = "nginx"
}

# ========================================
# OBSERVABILITY STACK
# ========================================
variable "grafana_enabled" {
  description = "Enable Grafana"
  type        = bool
  default     = true
}

variable "loki_enabled" {
  description = "Enable Loki"
  type        = bool
  default     = true
}

variable "tempo_enabled" {
  description = "Enable Tempo"
  type        = bool
  default     = true
}

variable "mimir_enabled" {
  description = "Enable Mimir"
  type        = bool
  default     = true
}

variable "pyroscope_enabled" {
  description = "Enable Pyroscope"
  type        = bool
  default     = true
}

variable "alloy_enabled" {
  description = "Enable Alloy"
  type        = bool
  default     = true
}

variable "otel_collector_enabled" {
  description = "Enable OpenTelemetry Collector"
  type        = bool
  default     = true
}

# ========================================
# VAULT CONFIGURATION
# ========================================
variable "vault_enabled" {
  description = "Install HashiCorp Vault (dev mode)"
  type        = bool
  default     = true
}

variable "vault_version" {
  description = "Vault Helm chart version"
  type        = string
  default     = "0.27.0"
}

variable "vault_root_token" {
  description = "Vault dev root token"
  type        = string
  sensitive   = true
  default     = "root"
}

# ========================================
# EXTERNAL SECRETS OPERATOR CONFIGURATION
# ========================================
variable "eso_enabled" {
  description = "Install External Secrets Operator"
  type        = bool
  default     = true
}

variable "eso_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.10.0"
}

# ========================================
# RESOURCE LIMITS
# ========================================
variable "resource_requests" {
  description = "Default resource requests"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "64Mi"
  }
}

variable "resource_limits" {
  description = "Default resource limits"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "128Mi"
  }
}

# ========================================
# CUSTOM VALUES
# ========================================
variable "custom_values" {
  description = "Custom Helm values (as YAML string or map)"
  type        = any
  default     = {}
}
