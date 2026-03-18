# Variables for Kind Cluster

variable "kind_cluster_name" {
  description = "Kind cluster name"
  type        = string
  default     = "asus-local"
}

variable "kind_version" {
  description = "Kubernetes version for Kind nodes"
  type        = string
  default     = "v1.29.0"
}

variable "kind_node_image" {
  description = "Kind node image"
  type        = string
  default     = "kindest/node:v1.29.0@sha256:eaa1450915475849a73a9227b8f201df25e55e268e5d619312131292e324d570"
}

variable "create_kind_cluster" {
  description = "Create Kind cluster"
  type        = bool
  default     = true
}

variable "kind_config_path" {
  description = "Path to Kind cluster configuration"
  type        = string
  default     = "cluster/config.yaml"
}

# Addons configuration
variable "install_cilium" {
  description = "Install Cilium CNI"
  type        = bool
  default     = true
}

variable "cilium_version" {
  description = "Cilium helm chart version"
  type        = string
  default     = "1.15.0"
}

variable "install_metrics_server" {
  description = "Install Metrics Server"
  type        = bool
  default     = true
}

variable "install_metallb" {
  description = "Install MetalLB"
  type        = bool
  default     = true
}

variable "metallb_version" {
  description = "MetalLB version"
  type        = string
  default     = "0.13.7"
}

variable "install_ingress_nginx" {
  description = "Install Nginx Ingress Controller"
  type        = bool
  default     = true
}

variable "ingress_nginx_version" {
  description = "Nginx Ingress Controller version"
  type        = string
  default     = "4.10.1"
}

variable "enable_inotify_tuning" {
  description = "Enable inotify system tuning"
  type        = bool
  default     = true
}
