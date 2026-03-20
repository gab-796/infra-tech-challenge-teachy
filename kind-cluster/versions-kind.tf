# Kind Cluster Terraform Configuration

# Provider local para executar scripts
terraform {
  backend "s3" {
    bucket                      = "tfstate"
    key                         = "cluster/terraform.tfstate"
    region                      = "us-east-1"
    endpoints = {
      s3 = "http://localhost:9100"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }

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
