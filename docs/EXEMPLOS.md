# Exemplos de uso - Terraform Helm Deployment

## 1. SETUP INICIAL

# Clonar/acessar a pasta
cd terraform-helm/

# Inicializar (faz download dos providers)
make init
# ou
terraform init


## 2. DEPLOYMENT BÁSICO

# Ver o plano (sem aplicar)
make plan
# ou
terraform plan

# Deploiar tudo
make deploy
# ou
make apply

# Destruir recursos
make destroy


## 3. CUSTOMIZAR VALORES

# Opção A: Alterar terraform.tfvars
nano terraform.tfvars
make apply

# Opção B: Usar arquivo de valores personalizados
cp custom-values.yaml.example custom-values.yaml
nano custom-values.yaml
# Editar terraform.tfvars e descomentar:
# helm_values_file = "./custom-values.yaml"
make apply

# Opção C: Passar variaveis pela linha de comando
terraform apply -var="inventory_app_replicas=3" -var="inventory_app_image_tag=v3.1"

# Opção D: Usar arquivo .auto.tfvars (automático)
cat > production.auto.tfvars << EOF
inventory_app_image_tag = "v4.0"
inventory_app_replicas = 3
mysql_root_password = "senhaforte123!"
EOF
terraform apply


## 4. MONITORAR DEPLOYMENT

# Ver status
make status

# Ver logs em tempo real
make logs

# Ver logs do MySQL
make logs-mysql

# Descrever um pod específico
kubectl describe pod <pod-name> -n api-app-go

# Ver eventos
kubectl get events -n api-app-go


## 5. ACESSAR APLICAÇÃO

# Via Ingress (requer entrada no /etc/hosts)
curl http://inventory.local/health
curl http://inventory.local/metrics

# Via port-forward
make dash          # Porta 10000
make dash-mysql    # Porta 3306

# Via kubectl exec
make shell-app     # Shell na app
make shell-mysql   # MySQL shell


## 6. HELM OPERATIONS

# Ver releases
helm list -n api-app-go

# Ver histórico
helm history api-observabilidade -n api-app-go

# Rollback para versão anterior
helm rollback api-observabilidade 1 -n api-app-go

# Atualizar release
helm upgrade api-observabilidade ../helm-chart/infra-tech-challenge-teachy -n api-app-go

# Ver valores usados
make get-values


## 7. TROUBLESHOOTING

# Ver todos os recursos
kubectl get all -n api-app-go

# Ver estado do Terraform
make show
make state-list

# Ver outputs
make output

# Limpar plano anterior
make clean

# Validar sintaxe
make validate

# Formatar arquivos
make fmt


## 8. ATUALIZAR IMAGEM

# Opção 1: Via variável
terraform apply -var="inventory_app_image_tag=v3.1"

# Opção 2: Editar terraform.tfvars
sed -i 's/inventory_app_image_tag.*/inventory_app_image_tag  = "v3.1"/' terraform.tfvars
terraform apply

# Opção 3: Via Helm diretamente
helm upgrade api-observabilidade ../helm-chart/infra-tech-challenge-teachy \
  --set inventoryApp.image.tag=v3.1 \
  -n api-app-go


## 9. SCALING

# Aumentar replicas
terraform apply -var="inventory_app_replicas=3"

# Ou editar valores customizados
nano custom-values.yaml
# Alterar: inventoryApp.replicaCount: 3
terraform apply


## 10. BACKUP & RESTORE

# Backup do estado
cp terraform.tfstate terraform.tfstate.backup

# Exportar manifests atuais
kubectl get all -n api-app-go -o yaml > backup.yaml

# Importar release existente no Terraform
terraform import helm_release.api_observabilidade api-app-go/api-observabilidade


## 11. DEBUGGING

# Re-inicializar (em caso de erro)
terraform init -upgrade

# Ver saída detalhada
TF_LOG=DEBUG terraform plan

# Limpar cache
rm -rf .terraform/

# Plan com mais detalhes
terraform plan -out=tfplan && terraform show -json tfplan | jq


## 12. PREPARAR PARA PRODUÇÃO

# Usar remote backend
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "seu-bucket"
    key            = "api-observabilidade/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
EOF

# Migrar estado
terraform init -migrate-state

# Adicionar .gitignore
echo "terraform.tfstate*" >> .gitignore

# Usar workspace
terraform workspace new production
terraform workspace select production
terraform apply


## 13. REINSTALAÇÃO COMPLETA

# Destruir tudo e redeploiar
make reinstall

# Ou manualmente:
make destroy-force
rm -rf .terraform/
rm terraform.tfstate*
make init
make apply


## 14. MONITORAMENTO CONTÍNUO

# Shell script para monitoramento
watch -n 5 'kubectl get pods -n api-app-go'

# Ver alterações em tempo real
kubectl get pods -n api-app-go -w


## 15. CI/CD INTEGRATION

# Script simples para CI/CD
#!/bin/bash
set -e

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

echo "Deployment concluído!"
make status


# Exemplo GitHub Actions (em .github/workflows/deploy.yml):
# name: Terraform Deploy
# on: [push]
# jobs:
#   deploy:
#     runs-on: ubuntu-latest
#     steps:
#       - uses: actions/checkout@v2
#       - uses: hashicorp/setup-terraform@v1
#       - run: cd terraform-helm && terraform init
#       - run: cd terraform-helm && terraform apply -auto-approve
