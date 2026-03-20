# Infrastructure Technical Challenge — Kubernetes & Observability

Stack completa de observabilidade em Kubernetes local, provisionada 100% via **Terraform + Helm**, entregando métricas, logs, traces e profiling de uma aplicação Go instrumentada com OpenTelemetry.

---

## Stack

| Componente | Versão | Papel |
|---|---|---|
| inventory-app | v4.0 | API Go instrumentada (métricas, logs, traces, profiling) |
| Grafana | 11.6.0 | Visualização unificada (dashboards pré-configurados) |
| Mimir | 2.13.0 | Armazenamento de métricas (Prometheus-compatible) |
| Loki | 2.9.5 | Agregação de logs |
| Tempo | 2.6.0 | Distributed tracing |
| Pyroscope | 1.13.0 | Continuous profiling |
| Alloy | v1.9.1 | Sincronização de regras de alerta para o Mimir ruler |
| OTel Collector | 0.123.0 | DaemonSet receptor de traces/logs/métricas |
| AlertManager | 1.31.1 | Roteamento de alertas |
| MailHog | 5.2.3 | SMTP fake para testes de alertas |
| MinIO | latest | Object storage (Loki chunks + Mimir blocks + Terraform state) |
| Vault | 0.27.0 | Gerenciamento de secrets (dev mode) |
| External Secrets Operator | 0.10.0 | Sincroniza secrets do Vault para o K8s |
| kube-state-metrics | v2.18.0 | Métricas de estado dos objetos K8s |
| Cilium | 1.15.0 | CNI |
| MetalLB | 0.13.7 | Load balancer local |
| Nginx Ingress | 4.10.1 | Ingress controller |

> Arquitetura detalhada, diagramas de fluxo e decisões de design em [`docs/`](./docs/).

---

## Pré-requisitos

```bash
terraform  # >= 1.0
kubectl    # v1.29.0
helm       # >= 3.0
kind       # v0.27.0
docker     # v29.3.0
mc         # MinIO client (para o state backend local)
```

---

## Credenciais — antes de rodar

O projeto usa credenciais sensíveis que **nunca ficam no repositório**. Você precisa exportá-las no terminal antes de executar o `setup-all.sh`.

### Obrigatórias (sem default)

```bash
# Senha do MySQL (escolha a sua)
export TF_VAR_mysql_root_password="suasenha"

# Senha do MinIO — usada tanto no state backend Docker quanto no MinIO in-cluster
export MINIO_ROOT_USER="minio"
export MINIO_ROOT_PASSWORD="suasenha"
export TF_VAR_minio_root_password="$MINIO_ROOT_PASSWORD"
```

> `MINIO_ROOT_USER` e `MINIO_ROOT_PASSWORD` são lidas pelo `setup-all.sh` para iniciar o container Docker do MinIO state backend. `TF_VAR_minio_root_password` é usada pelo Terraform para injetar a senha no MinIO in-cluster via Vault + ESO.

### Com default no `terraform.tfvars`

O `vault_root_token` já tem o valor `"root"` definido no `terraform.tfvars` — adequado para ambiente local de desenvolvimento. Não é necessário exportar `TF_VAR_vault_root_token` a menos que queira usar um token diferente.

---

## Setup

Com as credenciais exportadas, execute:

```bash
bash setup-all.sh
```

O script apresenta um menu interativo com as opções:

| Opção | Ação |
|---|---|
| 1 | Criar Kind Cluster + Deploy App (completo) |
| 2 | Apenas criar o Kind Cluster |
| 3 | Apenas fazer deploy da App |
| 4 | Mostrar status dos pods/serviços |
| 5 | Destruir apenas a App (mantém o cluster) |
| 6 | Destruir tudo (App + Cluster + MinIO state) |

O fluxo completo (opção 1) executa:
1. Valida os pré-requisitos
2. Inicia o container Docker `minio-state` (state backend do Terraform)
3. Cria o cluster Kind (1 CP + 2 workers, Cilium, MetalLB, Nginx Ingress)
4. Executa `terraform apply` na raiz — provisiona Vault, ESO, AlertManager e o Helm release completo

> Para detalhes sobre variáveis disponíveis, customizações e decisões de design, consulte [`docs/delivery.md`](./docs/delivery.md).

---

## Acessos após deploy

Adicione ao `/etc/hosts`:

```
172.18.0.0 inventory.local grafana-web.local loki.local tempo.local mimir.local pyroscope.local alloy.local minio.local alertmanager.local mailhog.local
```

| Serviço | URL |
|---|---|
| Inventory App | http://inventory.local |
| Grafana | http://grafana-web.local |
| Mimir | http://mimir.local |
| Loki | http://loki.local |
| Tempo | http://tempo.local |
| Pyroscope | http://pyroscope.local |
| Alloy | http://alloy.local |
| MinIO | http://minio.local |
| AlertManager | http://alertmanager.local |
| MailHog | http://mailhog.local |

Grafana já vem com acesso anônimo como Admin e datasources pré-configurados (Mimir, Loki, Tempo, Pyroscope).

---

## Destruir o ambiente

Use o menu do `setup-all.sh` (opções 5 ou 6), ou manualmente:

```bash
# Só a stack (mantém o cluster Kind)
terraform destroy

# Cluster Kind também
cd kind-cluster && terraform destroy
```

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [`docs/delivery.md`](./docs/delivery.md) | Mapeamento completo de requisitos, decisões de design, variáveis e estrutura do projeto |
| [`docs/decisions.md`](./docs/decisions.md) | Problemas encontrados, soluções adotadas e trade-offs técnicos |
| [`docs/architecture.md`](./docs/architecture.md) | Diagramas de arquitetura, fluxo de observabilidade, secrets e networking |
| [`docs/fluxo-senhas.md`](./docs/fluxo-senhas.md) | Como as credenciais fluem do Vault até os pods via ESO |
| [`docs/infra-challenge.md`](./docs/infra-challenge.md) | Requisitos originais do challenge |

---

**Versão**: 1.0.0
**Última atualização**: 2026-03
**Autor**: Gabriel Rocha
