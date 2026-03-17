# Infrastructure Technical Challenge — Kubernetes & Observability

Stack completa de observabilidade em Kubernetes local, provisionada 100% via **Terraform + Helm**, entregando métricas, logs, traces e profiling de uma aplicação Go instrumentada com OpenTelemetry.

---

## Índice

- [Arquitetura](#arquitetura)
- [Stack Completa](#stack-completa)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Setup — Deploy Completo](#setup--deploy-completo)
- [Acessando os Serviços](#acessando-os-serviços)
- [Variáveis Disponíveis](#variáveis-disponíveis)
- [Decisões de Design](#decisões-de-design)
- [Destruir o Ambiente](#destruir-o-ambiente)
- [Troubleshooting](#troubleshooting)

---

## Arquitetura

> Diagramas Mermaid detalhados (componentes, fluxo de observabilidade, secrets, módulos Terraform, networking) em [`docs/architecture.md`](./docs/architecture.md).

```
                          ┌─────────────────────────────────────────────────────┐
                          │              Kind Cluster (1 CP + 2 Workers)         │
                          │                                                       │
   Browser / curl         │  ┌──────────┐    ┌────────────────────────────────┐  │
   ─────────────────────► │  │  Nginx   │───►│  Namespace: api-app-go         │  │
                          │  │ Ingress  │    │                                │  │
                          │  └──────────┘    │  ┌─────────────┐  ┌─────────┐ │  │
                          │                  │  │inventory-app│  │  MySQL  │ │  │
                          │                  │  │  (Go + OTEL)│  │  (8.0)  │ │  │
                          │                  │  └──────┬──────┘  └─────────┘ │  │
                          │                  │         │ OTLP gRPC            │  │
                          │                  │  ┌──────▼──────────────────┐  │  │
                          │                  │  │    OTel Collector        │  │  │
                          │                  │  │  (metrics/logs/traces)   │  │  │
                          │                  │  └──┬──────────┬────────────┘  │  │
                          │                  │     │          │               │  │
                          │                  │  ┌──▼──┐    ┌──▼──┐           │  │
                          │                  │  │Tempo│    │Mimir│           │  │
                          │                  │  │(trc)│    │(mtr)│           │  │
                          │                  │  └─────┘    └──┬──┘           │  │
                          │                  │                │ remote_write  │  │
                          │                  │  ┌─────┐  ┌────▼────┐         │  │
                          │                  │  │Loki │  │ Alloy   │         │  │
                          │                  │  │(log)│  │(scrape) │         │  │
                          │                  │  └──┬──┘  └─────────┘         │  │
                          │                  │     │                          │  │
                          │                  │  ┌──▼──────────────────────┐  │  │
                          │                  │  │        Grafana           │  │  │
                          │                  │  │  (dashboards unificados) │  │  │
                          │                  │  └─────────────────────────┘  │  │
                          │                  │                                │  │
                          │                  │  ┌──────────┐  ┌───────────┐  │  │
                          │                  │  │Pyroscope │  │AlertMgr + │  │  │
                          │                  │  │(profiling│  │MailHog    │  │  │
                          │                  │  └──────────┘  └───────────┘  │  │
                          │                  └────────────────────────────────┘  │
                          │                                                       │
                          │  ┌──────────────────────────────────────────────┐    │
                          │  │  Namespace: vault                             │    │
                          │  │  Vault (dev mode) ◄── External Secrets Op.  │    │
                          │  └──────────────────────────────────────────────┘    │
                          └─────────────────────────────────────────────────────┘
```

---

## Stack Completa

| Componente | Função | Versão |
|---|---|---|
| **inventory-app** | API Go instrumentada (métricas, logs, traces, profiling) | v4.0 |
| **MySQL** | Banco de dados da aplicação | 8.0 |
| **Grafana** | Visualização unificada (dashboards pré-configurados) | 11.6.0 |
| **Loki** | Agregação de logs | 2.9.5 |
| **Tempo** | Distributed tracing | 2.6.0 |
| **Mimir** | Armazenamento de métricas (Prometheus-compatible) | 2.13.0 |
| **Pyroscope** | Continuous profiling | 1.13.0 |
| **Alloy** | Coleta de métricas do cluster (scrape → Mimir) | v1.9.1 |
| **OTel Collector** | Recebe OTLP da app, roteia para Tempo/Mimir/Loki | 0.123.0 |
| **AlertManager** | Gerenciamento de alertas | via Helm |
| **MailHog** | Receptor SMTP fake para alertas (local) | v1.0.1 |
| **MinIO** | Object storage S3-compatible (disponível para backends) | latest |
| **Vault** | Gerenciamento de secrets (dev mode) | 0.27.0 |
| **External Secrets Operator** | Sincroniza secrets do Vault para o K8s | 0.10.0 |
| **kube-state-metrics** | Métricas de estado dos objetos K8s | v2.18.0 |
| **Nginx Ingress** | Roteamento HTTP externo | via Kind |

---

## Pré-requisitos

Ferramentas necessárias:

```bash
terraform  # >= 1.0
kubectl
helm       # >= 3.0
kind
docker
mc         # MinIO client (para setup do state backend local)
```

Verificação rápida:

```bash
bash setup-all.sh  # valida todos os pré-requisitos antes de subir
```

---

## Estrutura do Projeto

```
.
├── main.tf                  # Root: namespace + módulos
├── variables.tf             # Declaração de variáveis
├── outputs.tf               # Outputs (URLs, namespaces)
├── terraform.tfvars         # Valores padrão (sem senhas)
├── versions.tf              # Providers e versões
├── Makefile                 # Atalhos: make deploy, make destroy, make status...
├── setup-all.sh             # Script interativo: Kind + App em sequência
├── deploy.sh                # Deploy só da aplicação
│
├── kind-cluster/            # Módulo separado: provisiona o cluster Kind
│   ├── kind-cluster.tf      # Cria cluster Kind (1 CP + 2 workers)
│   ├── variables-kind.tf
│   ├── terraform-kind.tfvars
│   └── cluster/config.yaml  # Configuração do Kind (nodeLabels, portMappings)
│
├── modules/
│   ├── app/                 # Helm release principal (toda a stack)
│   ├── vault/               # Vault em dev mode + init de secrets
│   ├── external-secrets/    # ESO + ClusterSecretStore
│   └── alertmanager/        # AlertManager + MailHog
│
├── helm-chart/              # Chart Helm próprio (todos os componentes)
│   ├── values.yaml          # Valores padrão do chart
│   ├── templates/
│   │   ├── inventory-app.yaml
│   │   ├── grafana.yaml
│   │   ├── loki.yaml
│   │   ├── tempo.yaml
│   │   ├── mimir.yaml
│   │   ├── pyroscope.yaml
│   │   ├── alloy.yaml
│   │   ├── otel-collector.yaml
│   │   ├── mysql.yaml
│   │   ├── minio.yaml
│   │   ├── ingress.yaml
│   │   ├── alerting-rules.yaml
│   │   └── ...
│   └── dashboards/          # JSONs dos dashboards Grafana
│
└── docs/
    ├── troubelshooting.md   # Problemas conhecidos e soluções
    ├── fluxo-senhas.md      # Como secrets fluem (Vault → ESO → Pod)
    └── ...
```

---

## Setup — Deploy Completo

### 1. Clonar o repositório

```bash
git clone <repo-url>
cd infra-tech-challenge-teachy
```

### 2. Criar o cluster Kind

```bash
cd kind-cluster
terraform init
terraform apply -auto-approve
cd ..
```

Isso cria um cluster Kind com **1 control plane + 2 workers**, instala Nginx Ingress e configura as inotify settings necessárias.

### 3. Configurar /etc/hosts

```bash
echo "127.0.0.1 inventory.local grafana-web.local loki.local tempo.local mimir.local pyroscope.local alloy.local minio.local alertmanager.local mailhog.local" | sudo tee -a /etc/hosts
```

### 4. Configurar senhas (variáveis sensíveis)

As senhas **nunca** estão no repositório. Passe via variável de ambiente:

```bash
export TF_VAR_mysql_root_password="suasenha"
export TF_VAR_minio_root_password="suasenha"
export TF_VAR_vault_root_token="root"   # pode deixar "root" em dev
```

### 5. Deploy da stack completa

```bash
terraform init
terraform apply
```

Ou usando o Makefile:

```bash
make deploy   # init + validate + plan + apply
```

O Terraform provisionará, em ordem:
1. Namespace `api-app-go`
2. Vault (dev mode) + init de secrets
3. External Secrets Operator + ClusterSecretStore
4. AlertManager + MailHog
5. Helm release principal (toda a stack de observabilidade + app)
6. kube-state-metrics

### 6. Verificar status

```bash
make status
# ou
kubectl get pods -n api-app-go
helm list -n api-app-go
```

---

## Acessando os Serviços

| Serviço | URL |
|---|---|
| Inventory App | http://inventory.local |
| Grafana | http://grafana-web.local |
| Loki | http://loki.local |
| Tempo | http://tempo.local |
| Mimir | http://mimir.local |
| Pyroscope | http://pyroscope.local |
| Alloy | http://alloy.local |
| MinIO | http://minio.local |
| AlertManager | http://alertmanager.local |
| MailHog (emails) | http://mailhog.local |

Grafana já vem com **acesso anônimo como Admin** e datasources pré-configurados (Tempo, Loki, Mimir, Pyroscope).

---

## Variáveis Disponíveis

| Variável | Padrão | Descrição |
|---|---|---|
| `namespace` | `api-app-go` | Namespace principal |
| `inventory_app_image_tag` | `v4.0` | Tag da imagem da app |
| `inventory_app_replicas` | `1` | Replicas da app |
| `mysql_root_password` | — | **Sensível** — passar via `TF_VAR_` |
| `mysql_database` | `inventory` | Nome do banco |
| `mysql_storage_size` | `10Gi` | Tamanho do PVC do MySQL |
| `grafana_enabled` | `true` | Habilitar Grafana |
| `loki_enabled` | `true` | Habilitar Loki |
| `tempo_enabled` | `true` | Habilitar Tempo |
| `mimir_enabled` | `true` | Habilitar Mimir |
| `pyroscope_enabled` | `true` | Habilitar Pyroscope |
| `alloy_enabled` | `true` | Habilitar Alloy |
| `otel_collector_enabled` | `true` | Habilitar OTel Collector |
| `vault_enabled` | `true` | Habilitar Vault |
| `eso_enabled` | `true` | Habilitar External Secrets Operator |
| `alertmanager_enabled` | `true` | Habilitar AlertManager |
| `minio_root_password` | — | **Sensível** — passar via `TF_VAR_` |
| `helm_values_file` | `""` | Path para values customizado |
| `custom_values` | `{}` | Override direto de values via HCL |

---

## Decisões de Design

### Terraform como único orquestrador
Todo o ambiente — desde a criação do cluster Kind até o deploy de cada componente — é gerenciado pelo Terraform. Não há `kubectl apply` ou `helm install` manuais. O Makefile é apenas um wrapper de conveniência sobre os comandos Terraform.

### Helm chart próprio vs charts de terceiros
Optei por um único **chart Helm próprio** que encapsula todos os componentes da stack. Isso dá controle total sobre os templates, facilita o rastreamento de mudanças via diff de values e elimina a necessidade de gerenciar múltiplos `helm_release` no Terraform para componentes interdependentes.

### Detecção automática de mudanças no chart
O `helm_release` no módulo `app` calcula um hash SHA256 de todos os arquivos do chart local:
```hcl
set {
  name  = "global.chartChecksum"
  value = sha256(join("", [for f in sort(tolist(fileset(var.helm_chart_path, "**"))) : filesha256(...)]))
}
```
Isso garante que qualquer mudança em template ou values dispara um `helm upgrade` automaticamente no próximo `terraform apply`.

### Secrets via Vault + External Secrets Operator
Senhas (MySQL, MinIO) são injetadas no Vault durante o `terraform apply` e consumidas pelos pods via ExternalSecret → Secret do Kubernetes. Isso evita colocar senhas em ConfigMaps ou variáveis de ambiente diretas nos manifests.

O Vault roda em **dev mode** (sem persistência, auto-unsealed, token fixo) — adequado para ambiente local de desenvolvimento. Ver [`docs/troubelshooting.md`](./docs/troubelshooting.md) para a explicação completa de por que não usar modo production.

### AlertManager sem PVC
O AlertManager usa StatefulSet com `volumeClaimTemplates`, o que causa PVCs órfãos após `terraform destroy` (o Kubernetes nunca deleta PVCs de StatefulSet automaticamente). Para um ambiente local onde o histórico de silences é descartável, a persistência foi desabilitada (`persistence.enabled: false`). Ver [`docs/troubelshooting.md`](./docs/troubelshooting.md) para detalhes.

### Merge shallow do Terraform
O `merge()` do Terraform é shallow — ao sobrescrever um objeto no `locals`, todas as chaves filhas do values.yaml são perdidas. Por isso, cada bloco no `locals` do módulo `app` precisa declarar explicitamente as chaves que o chart referencia nos templates.

---

## Destruir o Ambiente

```bash
# Só a stack (mantém o cluster)
make destroy
# ou
terraform destroy

# Cluster Kind também
cd kind-cluster && terraform destroy
```

> **Atenção:** o `terraform destroy` limpa PVCs e PVs de todos os componentes gerenciados pelo Helm. O AlertManager não gera PV pois está com persistência desabilitada.

---

## Troubleshooting

Ver [`docs/troubelshooting.md`](./docs/troubelshooting.md) para problemas conhecidos:

- PV/PVC fantasma do AlertManager
- `too many open files` no Kind
- Mudança do Alloy para OTel na coleta de logs
- Vault em dev mode — por que sem PVC

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
