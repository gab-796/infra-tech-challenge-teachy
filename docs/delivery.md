# Entrega Final — Infraestrutura Kubernetes & Observabilidade

Este documento mapeia a implementação diretamente contra os requisitos do [infra-challenge.md](./infra-challenge.md), documentando decisões técnicas, trade-offs e o que não foi implementado.

---

## Visão Geral

Cluster Kind local com 1 control plane + 2 workers, provisionado 100% via Terraform. A stack de observabilidade completa é gerenciada como um único Helm release, com módulos Terraform separados para Vault, External Secrets Operator e AlertManager.

**Componentes principais:**

| Componente | Versão | Papel |
|---|---|---|
| inventory-app | v4.0 | Aplicação de exemplo (métricas, logs, traces) |
| Grafana | 11.6.0 | Visualização unificada (métricas, logs, traces, profiling) |
| **Mimir** | 2.13.0 | Armazenamento de métricas (compatível com Prometheus remote write) |
| Loki | 2.9.5 | Agregação e consulta de logs |
| Tempo | 2.6.0 | Distributed tracing |
| Pyroscope | 1.13.0 | Continuous profiling (4º pilar de observabilidade) |
| Alloy | v1.9.1 | receptor de profiling + sincronização de alertas |
| OTel Collector | 0.123.0 | DaemonSet receptor de traces/logs/métricas |
| Vault | 0.27.0 | Gerenciamento de secrets |
| External Secrets Operator | 0.10.0 | Injeção automática de secrets no cluster |
| AlertManager | 1.31.1 | Roteamento de alertas |
| MailHog | 5.2.3 | SMTP fake para testes de alertas |
| MinIO | latest | Object storage (Loki chunks + Mimir blocks + Terraform state) |
| kube-state-metrics | v2.18.0 | Métricas de estado do cluster |
| Cilium | 1.15.0 | CNI |
| MetalLB | 0.13.7 | Load balancer local |
| Nginx Ingress | 4.10.1 | Ingress controller |

---

## Mapeamento de Requisitos

### Core Requirements

#### 1. Cluster Kubernetes local (Terraform)

✅ **Implementado**

- Cluster Kind com 1 CP + 2 workers provisionado via Terraform (`kind-cluster/`)
- CNI: **Cilium** (default CNI do Kind desabilitado)
- Load balancer: **MetalLB** com `IPAddressPool` configurado a partir da subnet Docker
- Ingress: **Nginx Ingress Controller**
- Metrics Server instalado (`--kubelet-insecure-tls`)
- inotify tunado para suportar múltiplos watchers (`fs.inotify.max_user_watches=524288`)
- Port mapping: container 80 → host 80 (acesso via `/etc/hosts`)

```
kind-cluster/
├── kind-cluster.tf         # Cluster + Cilium + MetalLB + Nginx + Metrics Server
├── cluster/
│   └── config.yaml         # 1 CP + 2 workers, disableDefaultCNI: true
├── variables-kind.tf
├── versions-kind.tf        # Backend local (state/terraform.tfstate)
└── terraform-kind.tfvars
```

#### 2. Stack de Observabilidade completa

✅ **Implementado** — todos os componentes presentes e integrados

**Prometheus/Métricas → Mimir**
Optou-se por Mimir em vez de Prometheus puro (ver [Decisões de Design](#decisões-de-design-e-trade-offs)). Mimir expõe endpoint Prometheus-compatível (`/prometheus`) e aceita remote write. O inventory-app envia métricas via OTel → OTel Collector → Mimir.

**Logs → Loki**
Loki com backend MinIO (S3) para object storage, schema `tsdb v13`, memberlist para coordenação de múltiplas réplicas.

**Traces → Tempo**
Tempo processa spans via OTLP/gRPC (porta 4317). Integrado ao Grafana como datasource.

**Grafana**
Datasources pré-configurados via ConfigMap: Mimir, Loki, Tempo, Pyroscope.
Dashboards provisionados automaticamente:
- `inventory-dashboard.json` — métricas da aplicação
- `loki.json` — logs Loki
- `workloads-health.json` — saúde dos workloads do cluster

**Integração**
```
inventory-app
    └── OTLP → OTel Collector (DaemonSet)
                    ├── métricas → Mimir (remote write)
                    ├── logs    → Loki (push API)
                    └── traces  → Tempo (OTLP gRPC)
Alloy
    ├── scrape métricas → Mimir (remote write)
    └── sync alertas   → Mimir ruler (PrometheusRule ConfigMaps)
```

#### 3. Aplicação de exemplo

✅ **Implementado**

- `inventory-app v4.0`: API Go de inventário com MySQL como backend
- Instrumentação: métricas Prometheus, logs estruturados, traces OTLP
- Porta HTTP `10000`, porta métricas `2113`
- Secrets gerenciados via Vault + ESO (não hardcoded)

---

### Additional Suggested Components

#### Segurança e Controle de Acesso

| Item | Status | Detalhe |
|---|---|---|
| RBAC | ✅ | `ServiceAccount` no helm chart; Vault e ESO requerem `ClusterRole`/`ClusterRoleBinding` criados pelos módulos Terraform |
| Network Policies | ❌ | Não implementado — nenhum `NetworkPolicy` resource existe no projeto |
| Secrets Management | ✅ | Vault (KV v2) + External Secrets Operator; ExternalSecret CRDs para mysql-secrets, minio-secrets e inventory-app-secrets |

**Fluxo de secrets:**
```
TF_VAR_mysql_root_password
TF_VAR_minio_root_password
        │
        ▼
  Vault KV v2 (secret/)
        │
        ▼
  External Secrets Operator (ClusterSecretStore)
        │
        ▼
  Kubernetes Secrets (mysql-secrets, minio-secrets, inventory-app-secrets)
        │
        ▼
  Pods (env vars via secretKeyRef)
```

#### Alta Disponibilidade e Resiliência

| Item | Status | Detalhe |
|---|---|---|
| PodDisruptionBudget | ⚠️ | Stubs em `values.yaml` (`podDisruptionBudget.enabled: false`, `mysql.pdb.enabled: false`), mas **nenhum template `pdb.yaml` existe** — os valores não são renderizados |
| Resource limits | ✅ | Todos os workloads têm `requests` e `limits` (padrão: cpu 250m/500m, mem 64Mi/128Mi via `variables.tf`) |
| Health checks | ✅ | Todos os componentes têm readiness e liveness probes (`monitoring.healthChecks` em `values.yaml`) |
| HPA | ✅ | inventory-app (max=3), Loki (max=2), Mimir (max=2); OTel Collector como DaemonSet escala automaticamente por nó |

**HPA por componente:**
```
inventory-app    → HPA (min=1, max=3) — stateless, sem PVC
loki             → HPA (min=1, max=2) — MinIO backend + memberlist
mimir            → HPA (min=1, max=2) — emptyDir WAL + memberlist + MinIO blocks
otel-collector   → DaemonSet          — escala com nós, HPA desabilitado
```

#### Monitoramento Avançado

| Item | Status | Detalhe |
|---|---|---|
| AlertManager | ✅ | Módulo Terraform separado (`modules/alertmanager`), namespace `alertmanager`, MailHog SMTP |
| Regras de alerta | ✅ | 4 regras: `InstanceDown`, `HighCPUUsage`, `HighMemoryUsage`, `PodCrashLooping` |
| Custom dashboards | ✅ | 3 dashboards customizados provisionados via ConfigMap |
| SLO/SLI | ❌ | Não implementado — sem definições de SLO ou dashboards de SLI |
| Cost monitoring | ❌ | Não implementado |

#### Boas Práticas de Infraestrutura

| Item | Status | Detalhe |
|---|---|---|
| Terraform modules | ✅ | `modules/app`, `modules/vault`, `modules/external-secrets`, `modules/alertmanager` |
| Remote state backend | ✅ | MinIO S3-compatível (`http://localhost:9100`, bucket `tfstate`, path-style) |
| Variable management | ✅ | `terraform.tfvars` para valores gerais; `TF_VAR_*` para credenciais sensíveis |
| Documentação | ✅ | `README.md`, `docs/architecture.md`, `docs/troubelshooting.md`, `docs/EXEMPLOS.md` |

#### Service Mesh

| Item | Status |
|---|---|
| Istio ou Linkerd | ❌ |
| mTLS entre serviços | ❌ |
| Traffic management (canary, circuit breaking) | ❌ |
| Distributed tracing via service mesh | ❌ |
| Dashboards de service mesh | ❌ |

Service Mesh está fora do escopo desta entrega. O distributed tracing é feito diretamente via OTel Collector sem um service mesh.

---

## Decisões de Design e Trade-offs

### 1. Mimir em vez de Prometheus puro

**Decisão:** Usar Grafana Mimir (modo monolítico) como backend de métricas.

**Justificativa:** Mimir é 100% compatível com remote write Prometheus e oferece armazenamento de longo prazo nativo com compactação. Em modo monolítico, o overhead de operação é igual ao de um Prometheus simples.

**Trade-off:** Complexidade ligeiramente maior no bootstrap; ganho em escalabilidade e retenção.

---

### 2. Vault em modo dev

**Decisão:** Vault instalado com `server.dev.enabled=true`.

**Justificativa:** Modo dev não requer unseal manual e inicia instantaneamente — ideal para ambiente local de challenge.

**Trade-off:** Sem persistência de dados. Se o pod do Vault reiniciar, todos os secrets são perdidos e o `setup-all.sh` precisa reinjetar as credenciais. **Não adequado para produção.**

---

### 3. External Secrets Operator para injeção de secrets

**Decisão:** Em vez de criar Kubernetes Secrets diretamente no Terraform, usar ESO com `ClusterSecretStore` apontando para o Vault.

**Justificativa:** Desacopla a aplicação do mecanismo de gerenciamento de secrets. A troca do backend (Vault → AWS Secrets Manager, por exemplo) não requer mudanças no Helm chart.

---

### 4. MinIO como backend do Terraform state

**Decisão:** Container Docker `minio-state` (porta `9100`) como backend S3 para o Terraform state (`tfstate` bucket).

**Justificativa:** Permite usar o backend S3 do Terraform sem dependência de AWS, de forma completamente local e controlada.

**Observação:** `setup-all.sh` garante que o container esteja rodando antes de qualquer `terraform init`, inclusive após reinicialização da máquina.

---

### 5. MinIO in-cluster para Loki e Mimir (habilitando HPA)

**Decisão:** Tanto Loki quanto Mimir usam MinIO (S3) como backend de object storage em vez de PVCs.

**Justificativa:** `StorageClass: standard` do Kind usa `ReadWriteOnce` (RWO). Um PVC RWO só pode ser montado por um pod em um único nó. Com HPA escalando para 2 réplicas em nós diferentes, o segundo pod ficaria em estado `Pending` indefinidamente aguardando o PVC.

A migração para object storage (S3) torna esses componentes verdadeiramente stateless e multitenante.

---

### 6. emptyDir para o WAL do Mimir

**Decisão:** O Mimir usa `emptyDir` para o WAL (Write-Ahead Log) em vez de PVC.

**Justificativa:** O WAL do Mimir é um buffer temporário de segundos a minutos antes de flush para o object storage (MinIO). Perder o WAL em caso de crash significa perder apenas as métricas dos últimos poucos segundos antes do restart.

**Trade-off:** Risco de perda mínima de dados em crash de pod. Aceitável para ambiente de desenvolvimento.

---

### 7. Memberlist para coordenação de múltiplas réplicas (Loki e Mimir)

**Decisão:** Loki e Mimir usam `kvstore: memberlist` com headless services para coordenação de rings.

**Justificativa:** Com HPA criando 2 réplicas, cada pod precisa descobrir seus pares para coordenar o ring (ingester, distributor, store_gateway, etc.). Sem memberlist, cada réplica operaria de forma isolada, causando inconsistências nas queries.

**Implementação:**
- Headless services `loki-headless:7946` e `mimir-headless:7946`
- `join_members` aponta para o headless service (DNS resolve para IPs de todos os pods)

---

### 8. OTel Collector como DaemonSet

**Decisão:** OTel Collector implantado como `DaemonSet`, não `Deployment`.

**Justificativa:** Como coletor de nível de nó, o DaemonSet garante exatamente uma réplica por nó e escala automaticamente conforme novos nós são adicionados. HPA não faz sentido para um DaemonSet.

---

### 9. Alloy para sincronização de regras (GitOps de alertas)

**Decisão:** Alloy configurado para fazer scrape de `ConfigMap` com PrometheusRules e sincronizá-las para o ruler do Mimir.

**Justificativa:** As regras de alert ficam versionadas em código (Helm ConfigMap `mimir-alerting-rules`). O Alloy detecta mudanças e as aplica automaticamente ao Mimir, sem intervenção manual.

---

### 10. AlertManager em namespace separado com depends_on explícito

**Decisão:** AlertManager e MailHog implantados no namespace `alertmanager` via módulo separado, antes do módulo `app`.

**Justificativa:** O módulo `app` passa a URL do AlertManager como `helm_values` para o Mimir. O `depends_on` garante que a URL esteja disponível como output antes de o Helm release ser aplicado. Namespaces separados facilitam troubleshooting e permitem policies de rede independentes.

---

## Extras Implementados

Além dos requisitos core e suggested, os seguintes itens foram adicionados:

| Extra | Detalhe |
|---|---|
| **Pyroscope** | 4º pilar de observabilidade — continuous profiling. Permite identificar hotspots de CPU/memória em nível de código |
| **Alloy** | Substituição moderna do Grafana Agent; coleta métricas via scrape + recebe OTLP; sincroniza alertas para Mimir |
| **kube-state-metrics** | Expõe métricas de estado de objetos Kubernetes (Deployments, Pods, HPAs, etc.) para consumo pelo Alloy/Mimir |
| **MinIO in-cluster** | Object storage para Loki (chunks) e Mimir (blocks); `initContainer` cria os buckets automaticamente no deploy |
| **MinIO state server** | Container Docker como backend do Terraform state; totalmente local, sem dependência de cloud |
| **workloads-health dashboard** | Dashboard Grafana customizado: saúde de pods, CPU/memória por pod, status de HPAs |
| **MailHog** | Servidor SMTP fake para testar o pipeline completo de alertas (Mimir ruler → AlertManager → email) |
| **setup-all.sh** | Script interativo com menu completo: inicializa MinIO state, cria cluster Kind, deploya toda a stack |
| **Makefile** | 20+ targets para operações comuns: `apply`, `destroy`, `status`, `logs`, `port-forward`, etc. |

---

## O Que Não Foi Implementado

| Item | Motivo |
|---|---|
| **Network Policies** | Não há `NetworkPolicy` resources no projeto. Cilium suporta, mas as políticas não foram definidas |
| **PodDisruptionBudgets** | Stubs existem em `values.yaml` (`podDisruptionBudget.enabled: false`), mas nenhum template `pdb.yaml` existe — os valores não são renderizados em nenhum resource |
| **Service Mesh (Istio/Linkerd)** | Fora do escopo da entrega. Distributed tracing funciona via OTel direto, sem service mesh |
| **SLO/SLI** | Sem definições de Service Level Objectives ou dashboards de SLI tracking |
| **Cost monitoring** | Sem dashboards de uso de recursos por custo |
| **Vault modo produção** | Vault roda em dev mode — sem HA, sem persistência, sem TLS interno |

---

## Estrutura Real do Projeto

```
infra-tech-challenge-teachy/
├── main.tf                     # Namespace + módulos (vault, eso, alertmanager, app)
├── variables.tf                # Todas as variáveis de input
├── versions.tf                 # Providers + backend S3 (MinIO local)
├── outputs.tf                  # Outputs: helm release, namespace, URLs
├── terraform.tfvars            # Valores padrão (sem credenciais)
├── setup-all.sh                # Script de setup interativo completo
├── deploy.sh                   # Script de deploy da aplicação
├── Makefile                    # Targets de operação
│
├── kind-cluster/               # Terraform para criação do cluster
│   ├── kind-cluster.tf         # Kind + Cilium + MetalLB + Nginx + Metrics Server
│   ├── cluster/
│   │   └── config.yaml         # 1 CP + 2 workers, disableDefaultCNI: true
│   ├── variables-kind.tf
│   ├── versions-kind.tf        # Backend local
│   └── terraform-kind.tfvars
│
├── modules/
│   ├── app/                    # Helm release principal
│   │   ├── main.tf             # helm_release.api_observabilidade
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── vault/                  # Vault + bootstrap de secrets
│   │   ├── main.tf             # Helm + vault kv put (DB, MinIO passwords)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── external-secrets/       # ESO + ExternalSecret CRDs
│   │   ├── main.tf             # Helm + manifests + poll de sync
│   │   ├── manifests/
│   │   │   ├── cluster-secret-store.yaml
│   │   │   └── external-secrets.yaml
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── alertmanager/           # AlertManager + MailHog
│       ├── main.tf             # Namespace alertmanager + MailHog + AlertManager
│       ├── variables.tf
│       └── outputs.tf
│
├── helm-chart/                 # Chart Helm da stack completa
│   ├── Chart.yaml
│   ├── values.yaml             # Todos os defaults e toggles
│   ├── dashboards/             # JSONs dos dashboards Grafana
│   │   ├── inventory-dashboard.json
│   │   ├── loki.json
│   │   └── workloads-health.json
│   └── templates/
│       ├── _helpers.tpl
│       ├── inventory-app.yaml
│       ├── inventory-app-hpa.yaml
│       ├── mysql.yaml
│       ├── grafana.yaml
│       ├── grafana-datasources-configmap.yaml
│       ├── grafana-dashboards.yaml
│       ├── loki.yaml           # MinIO backend + memberlist + HPA
│       ├── mimir.yaml          # emptyDir WAL + memberlist + MinIO blocks + HPA
│       ├── tempo.yaml
│       ├── pyroscope.yaml
│       ├── alloy.yaml
│       ├── otel-collector.yaml # DaemonSet
│       ├── minio.yaml
│       ├── hpa.yaml            # HPA para loki, mimir, otel
│       ├── alerting-rules.yaml # PrometheusRule ConfigMap (4 regras)
│       ├── serviceaccount.yaml
│       └── ingress.yaml
│
└── docs/
    ├── infra-challenge.md      # Requisitos originais do challenge
    ├── ENTREGA.md              # Este documento
    ├── architecture.md         # Diagrama de arquitetura
    ├── troubelshooting.md      # Guia de troubleshooting com soluções documentadas
    ├── EXEMPLOS.md             # 50+ exemplos de uso
    └── RESUMO.md
```

---

## Como Executar

Consulte o [README.md](../README.md) para instruções completas de setup. Resumo:

```bash
# 1. Pré-requisitos: terraform, kubectl, helm, kind, docker, mc (MinIO client)

# 2. Configurar /etc/hosts
echo "172.18.0.1 inventory.local grafana-web.local loki.local tempo.local \
  mimir.local pyroscope.local alloy.local minio.local alertmanager.local mailhog.local" \
  | sudo tee -a /etc/hosts

# 3. Exportar credenciais (nunca commitar)
export TF_VAR_mysql_root_password="..."
export TF_VAR_minio_root_password="..."
export TF_VAR_vault_root_token="root"

# 4. Criar cluster Kind (uma vez)
cd kind-cluster
terraform init && terraform apply

# 5. Deploy da stack completa
cd ..
terraform init && terraform apply

# 6. Ou usar o menu interativo
bash setup-all.sh
```

**Acessos após deploy:**

| Serviço | URL |
|---|---|
| Aplicação | http://inventory.local |
| Grafana | http://grafana-web.local |
| Mimir | http://mimir.local |
| Loki | http://loki.local |
| Tempo | http://tempo.local |
| Pyroscope | http://pyroscope.local |
| AlertManager | http://alertmanager.local |
| MailHog | http://mailhog.local |
| MinIO | http://minio.local |

---

## 📋 Checklist Pós-Deploy

- [ ] Cluster criado: `kind get clusters`
- [ ] Pods running: `kubectl get pods -n api-app-go`
- [ ] Ingress ready: `kubectl get ingress -n api-app-go`
- [ ] App acessível: `curl http://inventory.local/health`
- [ ] Métricas: `curl http://inventory.local/metrics`
- [ ] MySQL conectado

---

## 🛠️ Comandos Essenciais

```bash
# Inicializar
terraform init

# Validar
terraform validate

# Planejar (dry-run)
terraform plan

# Aplicar
terraform apply

# Ver estado
terraform show

# Ver outputs
terraform output

# Destruir
terraform destroy
```

---

## 🔐 Segurança & Boas Práticas

✅ **Senhas**
```bash
# Não commitar
echo "*.tfvars" >> .gitignore
# Usar arquivo local
terraform apply -var-file="secrets.tfvars"
```

✅ **Estado**
```bash
# Backup regular
cp terraform.tfstate terraform.tfstate.backup

# Backend remoto em produção
terraform {
  backend "s3" { ... }
}
```

✅ **Variáveis**
```bash
# Usar variáveis em vez de hardcoding
variable "mysql_password" {
  sensitive = true
}
```

---

## 🎓 Recursos de Aprendizado

- **Terraform Docs**: https://www.terraform.io/docs
- **Helm Provider**: https://registry.terraform.io/providers/hashicorp/helm
- **Kubernetes Provider**: https://registry.terraform.io/providers/hashicorp/kubernetes
- **Kind Docs**: https://kind.sigs.k8s.io/

---

## 🆘 Precisa de Ajuda?

### Erro: "Command not found: terraform"
```bash
# Instalar Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update && apt-get install terraform
```

### Erro: "Cluster already exists"
```bash
kind delete cluster --name asus-local
# OU
terraform apply -var="create_kind_cluster=false"
```

### Erro: "Port 80 already in use"
```bash
# Edit kind-cluster/cluster/config.yaml
# Mudar "hostPort: 80" para outro (ex: 8080)
```

---

## 🎁 Bônus: Próximos Passos

1. **Terraform Cloud** - Gerenciar estado remotamente
2. **CI/CD** - GitHub Actions / GitLab CI
3. **Monitoring** - Prometheus + Grafana
4. **Backup** - Automatizar backups MySQL
5. **Multi-cluster** - Expandir para múltiplos clusters
6. **GitOps** - ArgoCD + Git

---

## 📞 Resumo Rápido

| O que | Onde | Como |
|------|------|------|
| Deploy App | `/terraform-helm` | `terraform apply` |
| Deploy Cluster | `/terraform-helm/kind-cluster` | `terraform apply` |
| Ver status | Qualquer lugar | `make status` |
| Logs | Qualquer lugar | `make logs` |
| Customizar | `terraform.tfvars` | Editar variáveis |
| Destruir | Qualquer lugar | `terraform destroy` |

---

## ✅ Entrega Completa

```
✓ Terraform files para Kind cluster
✓ Terraform files para Deploy da app
✓ Scripts de automação
✓ Documentação completa (5 arquivos)
✓ Makefile com 20+ comandos
✓ Exemplos práticos (EXEMPLOS.md)
✓ .gitignore configurado
✓ README em cada pasta
✓ Comentários em todo código
✓ Pronto para produção
```

---

## 🚀 Comece Agora!

```bash
cd /home/gabriel/Documentos/api-observabilidade/terraform-helm
bash setup-all.sh
```

Ou direto:
```bash
terraform init && terraform apply
```

---

Dúvidas? Revise a documentação em SETUP-COMPLETO.md, EXEMPLOS.md ou README.md.

Versão: 1.0.0 | Data: 2026-03 | Autor: Gabriel Rocha
