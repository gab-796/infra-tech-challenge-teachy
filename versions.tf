terraform {
    backend "local" {
    path = "state/terraform.tfstate"
  }

  required_version = ">= 1.0"

  required_providers {
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

provider "kubernetes" {
  config_path = var.kubeconfig_path
  # Alternativamente, você pode usar:
  # config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
    # config_context = var.kubeconfig_context
  }
}
