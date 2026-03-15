# Kind Cluster Setup via Terraform

Configuração do cluster Kind usando Terraform em vez de Makefile.

## 📋 Pré-requisitos

1. **Terraform** >= 1.0
2. **Kind** instalado
3. **Docker** rodando
4. **kubectl** configurado

## 🚀 Como Usar

### 1. Inicializar Terraform

```bash
cd kind-cluster
terraform init
```

### 2. Criar o cluster

```bash
terraform plan
terraform apply
```

### 3. Verificar o cluster

```bash
# Listar clusters Kind
kind get clusters

# Ver contexto
kubectl config current-context

# Ver nós
kubectl get nodes

# Ver addons instalados
kubectl get all -A
```

## 📝 Variáveis Disponíveis

| Variável | Tipo | Padrão | Descrição |
|----------|------|--------|-----------|
| `kind_cluster_name` | string | `asus-local` | Nome do cluster |
| `kind_version` | string | `v1.29.0` | Versão do Kubernetes |
| `create_kind_cluster` | bool | `true` | Criar cluster |
| `install_cilium` | bool | `true` | Instalar Cilium |
| `install_metrics_server` | bool | `true` | Instalar Metrics Server |
| `install_metallb` | bool | `true` | Instalar MetalLB |
| `install_ingress_nginx` | bool | `true` | Instalar Nginx Ingress |
| `install_vault` | bool | `false` | Instalar Vault |
| `install_minio` | bool | `true` | Instalar MinIO (S3-like) |
| `minio_namespace` | string | `minio` | Namespace do MinIO |
| `minio_root_user` | string | `minioadmin` | Usuário root do MinIO |
| `minio_root_password` | string | `minioadmin` | Senha root do MinIO |
| `minio_storage_size` | string | `50Gi` | Tamanho storage MinIO |
| `enable_inotify_tuning` | bool | `true` | Tunar inotify |

## 🔧 Customização

### Alterar nome do cluster

```bash
terraform apply -var="kind_cluster_name=meu-cluster"
```

### Instalar Vault também

```bash
terraform apply -var="install_vault=true"
```

### Desabilitar algum addon

```bash
terraform apply -var="install_metallb=false"
```

## 🛠️ Comandos Úteis

```bash
# Ver o que será alterado
terraform plan

# Ver estado atual
terraform show

# Destruir cluster (remove via Kind)
terraform destroy

# Port-forward Ingress
kubectl port-forward -n kube-system svc/ingress-nginx-controller 80:80 443:443

# Ver MetalLB pools
kubectl get ipaddresspools -n metallb-system

# Ver helm releases instaladas
helm list -A --kube-context=kind-asus-local
```

## 🪣 MinIO (S3-Compatible Storage)

MinIO é um servidor S3-compatible que permite simular AWS S3 localmente. Perfeito para testes de PVC com storage externo.

### Acessar MinIO

```bash
# Console (interface web)
# URL: http://minio-console.local
# User: minioadmin
# Password: minioadmin

# API (para aplicações)
# Endpoint: http://minio.local:9000
# Access Key: minioadmin
# Secret Key: minioadmin
```

### Criar bucket via CLI

```bash
# Instalar MC (MinIO Client)
brew install minio/stable/mc

# Alias
mc alias set minio http://minio.local:9000 minioadmin minioadmin

# Criar bucket
mc mb minio/api-data

# Listar
mc ls minio
```

### Usar MinIO em PVC

```bash
# Ver credentials
terraform output minio_credentials

# Exemplo de PVC usando MinIO
terraform output pvc_example
```

### Desabilitar MinIO

```bash
terraform apply -var="install_minio=false"
```

## ⚠️ Notas

- O cluster é criado com 1 control-plane + 2 workers
- Cilium é instalado como CNI (desabilita default CNI)
- MetalLB é configurado com a subnet do Docker
- Nginx Ingress é configurado para porta 80/443
- MinIO oferece storage S3-compatible para testes
- inotify é tuned para evitar "too many open files"

## 🗑️ Remover Cluster

```bash
terraform destroy
```

Ou manualmente:

```bash
kind delete cluster --name=asus-local
```

## 📚 Referências

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Terraform local-exec](https://www.terraform.io/language/resources/provisioners/local-exec)
- [Cilium Helm Chart](https://github.com/cilium/cilium/tree/master/install/kubernetes/cilium)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [MinIO Documentation](https://min.io/docs/)
- [MinIO Helm Chart](https://min.io/docs/minio/kubernetes/upstream/)

---

**Versão**: 1.0.0  
**Última atualização**: 2026-03
