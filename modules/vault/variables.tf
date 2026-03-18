variable "vault_enabled" {
  description = "Enable Vault installation"
  type        = bool
}

variable "vault_version" {
  description = "Vault Helm chart version"
  type        = string
}

variable "vault_root_token" {
  description = "Vault root token for dev mode"
  type        = string
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password to inject into Vault"
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "MinIO root password to inject into Vault"
  type        = string
  sensitive   = true
}
