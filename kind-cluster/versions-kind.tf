# Kind Cluster Terraform Configuration

# Provider local para executar scripts
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.3"
    }
  }
}

# Kubernetes provider
provider "kubernetes" {
  config_context   = var.kind_cluster_name != "" ? "kind-${var.kind_cluster_name}" : null
  config_path      = pathexpand("~/.kube/config")
  load_config_file = true
}

# Helm provider - uses kubernetes provider context
provider "helm" {
  kubernetes {
    config_context = var.kind_cluster_name != "" ? "kind-${var.kind_cluster_name}" : null
    config_path    = pathexpand("~/.kube/config")
  }
}
