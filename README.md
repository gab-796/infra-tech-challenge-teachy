# README.md - Terraform Helm Deployment

# Conversa da aplicação para Terraform with Helm

Este diretório contém a configuração completa do Terraform para fazer deploy da aplicação e suas dependências via **Helm Chart**.

## 📋 Pré-requisitos

1. **Terraform** instalado (recomendado v1.0+)
```bash
terraform version
```

2. **kubectl** instalado e configurado
```bash
kubectl config current-context
```

3. **Helm** instalado (recomendado v3.0+)
```bash
helm version
```

4. **Cluster Kubernetes** funcionando (Kind, Minikube, EKS, GKE, etc.)

5. **Nginx Ingress Controller** instalado (se usando ingress)
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
```

6. **DNS configurado** (adicionar ao `/etc/hosts`):
```
127.0.0.1 inventory.local
```

## 📁 Estrutura de Arquivos

```
terraform-helm/
├── versions.tf          # Provider versions e requirements
├── main.tf             # Recursos principais (Helm release, namespace)
├── variables.tf        # Declaração de variáveis
├── outputs.tf          # Outputs do Terraform
├── terraform.tfvars    # Valores padrões das variáveis
└── README.md          # Este arquivo
```

## 🚀 Como Usar

### 1. Inicializar o Terraform

```bash
cd terraform-helm
terraform init
```

### 2. Validar a configuração

```bash
terraform validate
```

### 3. Revisar o plano de deployment

```bash
terraform plan -out=tfplan
```

Este comando mostra todos os recursos que serão criados.

### 4. Aplicar a configuração

```bash
terraform apply tfplan
```

Ou aplicar direto sem salvar o plano:

```bash
terraform apply
```

### 5. Verificar o status

Após o deployment, você pode verificar:

```bash
# Ver todos os recursos criados
kubectl get all -n api-app-go

# Ver o Helm release
helm list -n api-app-go

# Ver detalhes do release
helm status api-observabilidade -n api-app-go

# Ver os valores usados
helm get values api-observabilidade -n api-app-go
```

### 6. Acessar a aplicação

Se estiver usando Ingress:

```bash
# Adicionar ao /etc/hosts (se não fez ainda)
echo "127.0.0.1 inventory.local" | sudo tee -a /etc/hosts

# Acessar via curl
curl http://inventory.local/health

# Acessar métricas
curl http://inventory.local/metrics
```

Ou usar port-forward:

```bash
kubectl port-forward -n api-app-go deployment/inventory-app 10000:10000
# Depois acessar em: http://localhost:10000
```

## 🔧 Customização

### Alterar valores via variáveis

Edit `terraform.tfvars`:

```hcl
inventory_app_image_tag  = "v3.1"
inventory_app_replicas   = 3
mysql_root_password      = "sua_senha_segura"
```

### Usar arquivo de valores customizado

1. Criar arquivo `custom-values.yaml`:

```yaml
grafana:
  enabled: true
  ingress:
    enabled: true
    hosts:
      - grafana.local

loki:
  enabled: true
  persistence:
    size: 50Gi
```

2. Atualizar em `terraform.tfvars`:

```hcl
helm_values_file = "./custom-values.yaml"
```

3. Reaplica:

```bash
terraform plan
terraform apply
```

### Alterar versão da imagem

```bash
terraform plan -var="inventory_app_image_tag=v3.1"
terraform apply -auto-approve -var="inventory_app_image_tag=v3.1"
```

## 📊 Variáveis Disponíveis

| Variável | Tipo | Padrão | Descrição |
|----------|------|--------|-----------|
| `kubeconfig_path` | string | `~/.kube/config` | Caminho do kubeconfig |
| `namespace` | string | `api-app-go` | Namespace do K8s |
| `inventory_app_image_tag` | string | `v4.0` | Tag da imagem da app |
| `inventory_app_replicas` | number | `1` | Replicas da app |
| `mysql_root_password` | string | `rootpassword` | Senha do MySQL |
| `mysql_database` | string | `inventory` | Nome do database |
| `mysql_storage_size` | string | `10Gi` | Tamanho do storage MySQL |
| `ingress_hostname` | string | `inventory.local` | Hostname do ingress |
| `grafana_enabled` | bool | `true` | Habilitar Grafana |
| `loki_enabled` | bool | `true` | Habilitar Loki |
| `tempo_enabled` | bool | `true` | Habilitar Tempo |
| `mimir_enabled` | bool | `true` | Habilitar Mimir |
| `pyroscope_enabled` | bool | `true` | Habilitar Pyroscope |
| `alloy_enabled` | bool | `true` | Habilitar Alloy |
| `otel_collector_enabled` | bool | `true` | Habilitar OpenTelemetry |

## 🗑️ Destruir os Recursos

Para remover tudo que foi criado:

```bash
terraform destroy
```

Confirme digitando `yes` quando solicitado.

Ou destruir sem confirmação:

```bash
terraform destroy -auto-approve
```

## 📝 Estados Terraform

O arquivo `terraform.tfstate` mantém o estado dos recursos. **Importante para produção**:

```bash
# Fazer backup do estado
cp terraform.tfstate terraform.tfstate.backup

# Em produção, usar remote backend (S3, GCS, Terraform Cloud, etc.)
```

## 🔐 Segurança

⚠️ **Importante**: 

- **Nunca commit `terraform.tfstate`** em Git
- **Nunca commit `terraform.tfvars`** com senhas
- Usar `terraform.tfvars.local` ignorado pelo Git
- Usar secrets management (Vault, AWS Secrets Manager, etc.)

Criar `.gitignore`:

```
terraform.tfstate*
terraform.tfvars.local
.terraform/
crash.log
```

## 🛠️ Comandos Úteis

```bash
# Validar sintaxe
terraform validate

# Formatar arquivos
terraform fmt -recursive

# Ver estado atual
terraform show

# Ver estado de um recurso específico
terraform show -json | jq '.values.root_module.resources[] | select(.address == "helm_release.api_observabilidade")'

# Importar recurso existente
terraform import helm_release.api_observabilidade api-app-go/api-observabilidade

# Atualizar lock files
terraform get -update

# Listar outputs
terraform output
```

## 📞 Troubleshooting

### Erro: `Unable to read local kubeconfig`

```bash
# Verificar se o arquivo existe
ls -la ~/.kube/config

# Ou especificar manualmente
terraform apply -var="kubeconfig_path=/path/to/kubeconfig"
```

### Erro: `namespace already exists`

```bash
terraform apply -var="create_namespace=false"
```

### Verificar logs da release Helm

```bash
helm get all api-observabilidade -n api-app-go
```

### Destruir apenas a release Helm mantendo namespace

```bash
terraform destroy -target helm_release.api_observabilidade
```

## 📚 Referências

- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Helm Charts Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 🎯 Próximos Passos

1. **Customizar Helm values** para seu ambiente
2. **Configurar remote backend** para estado compartilhado
3. **Setup de Prometheus** para monitoramento do Terraform
4. **Integrar com CI/CD** (GitHub Actions, GitLab CI, etc.)
5. **Configurar backups** do banco de dados
6. **Setup de logging** centralizado

---

**Versão**: 1.0.0  
**Última atualização**: 2026-03  
**Autor**: Gabriel Rocha
