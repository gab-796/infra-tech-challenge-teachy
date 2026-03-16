variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
}

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "helm_values_file" {
  description = "Path to an optional values file to merge"
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Helm chart version"
  type        = string
}

variable "inventory_app_replicas" {
  description = "Number of replicas for the inventory app"
  type        = number
}

variable "inventory_app_image_tag" {
  description = "Docker image tag for the inventory app"
  type        = string
}

variable "inventory_app_http_port" {
  description = "HTTP port for the inventory app"
  type        = number
}

variable "inventory_app_metrics_port" {
  description = "Metrics port for the inventory app"
  type        = number
}

variable "mysql_image_tag" {
  description = "Docker image tag for MySQL"
  type        = string
}

variable "mysql_database" {
  description = "MySQL database name"
  type        = string
}

variable "mysql_storage_size" {
  description = "MySQL PVC storage size"
  type        = string
}

variable "grafana_enabled" {
  description = "Enable Grafana"
  type        = bool
}

variable "loki_enabled" {
  description = "Enable Loki"
  type        = bool
}

variable "tempo_enabled" {
  description = "Enable Tempo"
  type        = bool
}

variable "mimir_enabled" {
  description = "Enable Mimir"
  type        = bool
}

variable "pyroscope_enabled" {
  description = "Enable Pyroscope"
  type        = bool
}

variable "alloy_enabled" {
  description = "Enable Alloy"
  type        = bool
}

variable "otel_collector_enabled" {
  description = "Enable OpenTelemetry Collector"
  type        = bool
}

variable "custom_values" {
  description = "Custom Helm values to merge (highest priority)"
  type        = any
  default     = {}
}
