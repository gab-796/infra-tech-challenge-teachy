# Complete Terraform Infrastructure Setup

Guia completo para provisionar o cluster Kind + aplicação via Terraform.

## 📋 Estrutura

```
terraform-helm/
├── kind-cluster/          # Provisionamento do cluster Kind
│   ├── versions-kind.tf
│   ├── variables-kind.tf
│   ├── kind-cluster.tf
│   ├── outputs-kind.tf
│   ├── terraform-kind.tfvars
│   ├── cluster/
│   │   └── config.yaml    # Configuração Kind
│   └── Makefile-terraform
│
└── (main terraform files) # Deploy da aplicação
    ├── versions.tf
    ├── variables.tf
    ├── main.tf
    ├── outputs.tf
    ├── terraform.tfvars
    └── Makefile
```

## 🚀 Quick Start (Tudo de Uma Vez)

### Passo 1: Criar Cluster Kind

```bash
cd terraform-helm/kind-cluster

# Preview
terraform plan

# Criar
terraform apply

# Verificar
terraform output
```

### Passo 2: Deploy Aplicação

```bash
cd ..

# Usar kubeconfig do Kind
export KUBECONFIG=~/.kube/config

# Preview
terraform plan

# Deploy
terraform apply
```

## 📊 Workflow Recomendado

### Setup Inicial Completo

```bash
# 1. Começar no root do projeto
cd terraform-helm/

# 2. Criar cluster
cd kind-cluster
make -f Makefile-terraform init
make -f Makefile-terraform create
cd ..

# 3. Deploy aplicação
make init
make apply

# 4. Verificar
kubectl get all -n api-app-go
helm list -n api-app-go
```

### Commands Equivalentes (com Terraform direto)

```bash
# Init + Plan + Apply (Kind)
cd kind-cluster
terraform init
terraform plan -out=tfplan-kind
terraform apply tfplan-kind

# Back to main terraform
cd ..
terraform init
terraform plan -out=tfplan-app
terraform apply tfplan-app
```

## 🔧 Customizações

### Alterar Nome do Cluster

```bash
cd kind-cluster
terraform apply -var="kind_cluster_name=meu-cluster"

# Depois sincronize no arquivo principal:
cd ..
terraform apply
```

### Usar Cluster Existente

Se o cluster Kind já existe:

```bash
cd kind-cluster
terraform import null_resource.kind_cluster_create kind_cluster_create
# OU simplesmente execute:
terraform apply -var="create_kind_cluster=false"
```

### Customizar Aplicação

```bash
cd terraform-helm
terraform apply -var="inventory_app_replicas=3" -var="inventory_app_image_tag=v3.1"
```

## 🛠️ Comandos Úteis Combinados

### Ver Status Completo

```bash
# Kind Cluster
cd kind-cluster
terraform output

# Aplicação
cd ..
terraform output
```

### Destruir Tudo (Na Ordem Correta!)

```bash
# PRIMEIRO: remover aplicação
cd terraform-helm
terraform destroy

cd kind-cluster
terraform destroy

# OU force:
kind delete cluster --name asus-local
```

### Verificar Logs

```bash
# Logs da aplicação
kubectl logs -n api-app-go deployment/inventory-app -f

# Logs do MySQL
kubectl logs -n api-app-go deployment/mysql -f

# Logs de todos os pods
kubectl logs -n api-app-go -l app=inventory-app -f
```

### Port Forward

```bash
# Aplicação (10000:10000)
kubectl port-forward -n api-app-go deployment/inventory-app 10000:10000

# MySQL (3306:3306)
kubectl port-forward -n api-app-go deployment/mysql 3306:3306

# Grafana (3000:3000)
kubectl port-forward -n api-app-go deployment/grafana 3000:3000
```

## 📝 Variáveis de Ambiente

Para automatizar setup, exporte estas variáveis:

```bash
export CLUSTER_NAME="asus-local"
export NAMESPACE="api-app-go"
export APP_REPLICAS="1"
export MYSQL_PASSWORD="rootpassword"

# Depois rode:
cd kind-cluster
terraform apply -var="kind_cluster_name=$CLUSTER_NAME"

cd ../terraform-helm
terraform apply \
  -var="namespace=$NAMESPACE" \
  -var="inventory_app_replicas=$APP_REPLICAS" \
  -var="mysql_root_password=$MYSQL_PASSWORD"
```

## 🔐 Segurança

### Proteger Senhas

```bash
# Criar arquivo local (não committado)
cat > secrets.tfvars << EOF
mysql_root_password = "senhaforte123!"
EOF

# Usar na aplicação:
terraform apply -var-file="secrets.tfvars"
```

### Usar Terraform Cloud/Backend Remoto

```bash
# No kind-cluster/backend.tf:
terraform {
  backend "s3" {
    bucket = "seu-bucket"
    key    = "kind-cluster.tfstate"
    region = "us-east-1"
  }
}

terraform init -migrate-state
```

## 📦 Makefile Unificado (Alternativa)

Se preferir um único Makefile na raiz:

```bash
cat > Makefile << 'EOF'
.PHONY: help cluster-create cluster-destroy app-deploy app-destroy all-create all-destroy

help:
	@echo "Targets: cluster-create cluster-destroy app-deploy app-destroy all-create all-destroy"

cluster-create:
	cd kind-cluster && terraform init && terraform apply

cluster-destroy:
	cd kind-cluster && terraform destroy

app-deploy:
	terraform init && terraform apply

app-destroy:
	terraform destroy

all-create: cluster-create app-deploy

all-destroy: app-destroy cluster-destroy

.DEFAULT_GOAL := help
EOF
```

Depois:

```bash
make all-create   # Criar tudo
make all-destroy  # Remover tudo
```

## 🐛 Troubleshooting

### Erro: "cluster already exists"

```bash
cd kind-cluster
terraform apply -var="create_kind_cluster=false"
```

### Erro: "Cannot apply inotify tuning without sudo"

```bash
# Aplicar manualmente:
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

### Helm release falha após Kind estar pronto

```bash
# Aguardar um pouco mais
kubectl wait --for=condition=Ready node --all --timeout=600s

# Depois retry:
cd terraform-helm
terraform apply
```

### Estado fico corrompido

```bash
# Clean slate
rm -rf .terraform terraform.tfstate* .terraform.lock.hcl
terraform init
terraform apply
```

## 📚 Próximos Passos

1. **Persistent Storage**: Configurar PersistentVolumes para MySQL
2. **Backup**: Setup de backup automático
3. **Monitoring**: Integrar Prometheus + Grafana
4. **CI/CD**: GitHub Actions ou GitLab CI para deployment automático
5. **Multi-cluster**: Expandir para múltiplos clusters

## 📞 Referências

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Kubernetes Best Practices](https://kubernetes.io/docs/)

---

**Versão**: 1.0.0  
**Data**: 2026-03  
**Autor**: Gabriel Rocha
