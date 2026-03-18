variable "vault_enabled" {
  description = "Enable Vault (required for ESO to work)"
  type        = bool
}

variable "eso_enabled" {
  description = "Enable External Secrets Operator"
  type        = bool
}

variable "eso_version" {
  description = "ESO Helm chart version"
  type        = string
}

variable "namespace" {
  description = "Application namespace where vault-token secret will be created"
  type        = string
}

variable "vault_root_token" {
  description = "Vault root token used by ESO to authenticate"
  type        = string
  sensitive   = true
}
