terraform {
  backend "s3" {
    bucket                      = "tfstate"
    key                         = "observability/terraform.tfstate"
    region                      = "us-east-1"
    endpoints = {
      s3 = "http://localhost:9100"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
    # credenciais passadas via -backend-config no terraform init
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
