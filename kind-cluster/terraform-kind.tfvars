# Kind Cluster Terraform Configuration

# Default values for Kind cluster
kind_cluster_name = "asus-local"

# Kubernetes versions (Kind node image)
kind_version = "v1.29.0"

# Addons installation
install_cilium          = true
cilium_version          = "1.15.0"

install_metrics_server  = true

install_metallb         = true
metallb_version         = "0.13.7"

install_ingress_nginx   = true
ingress_nginx_version   = "4.10.1"

# System tuning
enable_inotify_tuning   = true

# Cluster configuration
create_kind_cluster     = true
kind_config_path        = "cluster/config.yaml"
