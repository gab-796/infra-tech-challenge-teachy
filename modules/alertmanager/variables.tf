variable "alertmanager_enabled" {
  description = "Enable AlertManager and MailHog installation"
  type        = bool
}

variable "alertmanager_version" {
  description = "AlertManager Helm chart version (prometheus-community/alertmanager)"
  type        = string
}

variable "mailhog_version" {
  description = "MailHog Helm chart version (codecentric/mailhog)"
  type        = string
}

variable "alertmanager_namespace" {
  description = "Kubernetes namespace where AlertManager and MailHog will be deployed"
  type        = string
  default     = "alertmanager"
}
