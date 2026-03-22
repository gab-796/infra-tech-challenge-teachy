# Contexto do Projeto: infra-tech-challenge-teachy

## O que é esse projeto

Stack completa de observabilidade em Kubernetes local (Kind), provisionada 100% via **Terraform + Helm**.
Inclui uma aplicação Go (`inventory-app`) instrumentada com OpenTelemetry e toda a pilha Grafana LGTM+P.

## Estrutura principal

```
kind-cluster/       # Terraform: cluster Kind (1 CP + 2 workers, Cilium, MetalLB, Nginx)
modules/
  vault/            # HashiCorp Vault (dev mode) + init de secrets
  external-secrets/ # ESO + ClusterSecretStore apontando para Vault
  alertmanager/     # AlertManager + MailHog SMTP fake
  app/              # helm_release principal (toda a stack observability)
helm-chart/         # Chart Helm próprio que encapsula todos os componentes
main.tf             # Raiz Terraform — orquestra os módulos
variables.tf        # Todas as variáveis do projeto
terraform.tfvars    # Defaults (não contém secrets sensíveis)
setup-all.sh        # Script interativo de setup (menu com 7 opções)
docs/               # Documentação: architecture, decisions, delivery, fluxo-senhas
```

## Stack de componentes

| Componente | Versão | Função |
|---|---|---|
| inventory-app | v4.0 | API Go + OpenTelemetry (métricas, logs, traces, profiling) |
| Grafana | 11.6.0 | Visualização unificada (datasources pré-configurados) |
| Mimir | 2.13.0 | Métricas long-term (Prometheus-compatible) |
| Loki | 2.9.5 | Logs |
| Tempo | 2.6.0 | Distributed tracing |
| Pyroscope | 1.13.0 | Continuous profiling |
| OTel Collector | 0.123.0 | DaemonSet receptor OTLP (gRPC :4317, HTTP :4318) |
| Alloy | v1.9.1 | Sincronização de regras de alerta para Mimir ruler |
| AlertManager | 1.31.1 | Roteamento de alertas |
| MailHog | 5.2.3 | SMTP fake para testes de alertas |
| MinIO | latest | Object storage (Loki chunks + Mimir blocks + Terraform state) |
| Vault | 0.27.0 | Gestão de secrets (dev mode) |
| External Secrets Operator | 0.10.0 | Sincroniza secrets Vault → K8s |
| Cilium | 1.15.0 | CNI |
| MetalLB | 0.13.7 | Load balancer local |
| Nginx Ingress | 4.10.1 | Ingress controller |

## Convenções importantes

### State backend remoto
O Terraform usa MinIO como backend S3-compatible. O MinIO roda em Docker local (`minio-state`, porta 9100).
Todo `terraform init` precisa passar as credenciais:
```bash
terraform init \
  -backend-config="access_key=$MINIO_ROOT_USER" \
  -backend-config="secret_key=$MINIO_ROOT_PASSWORD" \
  -migrate-state -force-copy
```

### Credenciais sensíveis (nunca ficam no repo)
Exportar antes de qualquer `terraform` ou `setup-all.sh`:
```bash
export TF_VAR_mysql_root_password="suasenha"
export MINIO_ROOT_USER="minio"
export MINIO_ROOT_PASSWORD="suasenha"
export TF_VAR_minio_root_password="$MINIO_ROOT_PASSWORD"
```
O `vault_root_token` tem default `"root"` no `terraform.tfvars` — adequado para dev local.

### Dependências entre módulos
```
kubernetes_namespace (root)
  └── module.vault
        └── module.external_secrets
              └── module.app ← também depende de module.alertmanager
  └── module.alertmanager
```

### Habilitação condicional de componentes
Todos os componentes opcionais têm variável `<nome>_enabled` (bool). Alternar em `terraform.tfvars` e re-aplicar.

### Auto-upgrade do Helm chart
O módulo `app` calcula SHA256 de todos os arquivos do `helm-chart/` → qualquer mudança no chart
dispara automaticamente um `helm upgrade` no próximo `terraform apply`.

## Fluxo de secrets
`Terraform` → escreve no Vault (KV v2) → `ESO` lê do Vault → cria `K8s Secret` → Pod monta como env var

## URLs pós-deploy

Adicionar no `/etc/hosts`: `172.18.0.0  inventory.local grafana-web.local loki.local tempo.local mimir.local pyroscope.local alloy.local minio.local alertmanager.local mailhog.local`

| Serviço | URL |
|---|---|
| Inventory App | http://inventory.local |
| Grafana | http://grafana-web.local (acesso anônimo Admin) |
| Mimir | http://mimir.local |
| Loki | http://loki.local |
| Tempo | http://tempo.local |
| Pyroscope | http://pyroscope.local |
| Alloy | http://alloy.local |
| MinIO | http://minio.local |
| AlertManager | http://alertmanager.local |
| MailHog | http://mailhog.local |

## Documentos de referência

| Arquivo | Conteúdo |
|---|---|
| `docs/architecture.md` | Diagramas Mermaid de todos os fluxos |
| `docs/decisions.md` | Trade-offs e problemas resolvidos |
| `docs/delivery.md` | Mapeamento completo dos requisitos do challenge |
| `docs/fluxo-senhas.md` | Fluxo detalhado Vault → ESO → Pod |
