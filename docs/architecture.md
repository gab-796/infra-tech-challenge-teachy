# Architecture Diagrams

## 1. Visão Geral dos Componentes

```mermaid
graph TB
    subgraph Internet["Acesso Externo"]
        Browser["Browser / curl"]
    end

    subgraph Kind["Kind Cluster — 1 Control Plane + 2 Workers"]
        Ingress["Nginx Ingress Controller"]

        subgraph NS_APP["Namespace: api-app-go"]
            App["inventory-app\n(Go + OpenTelemetry)"]
            MySQL["MySQL 8.0"]
            OTel["OTel Collector"]
            Grafana["Grafana"]
            Loki["Loki"]
            Tempo["Tempo"]
            Mimir["Mimir"]
            Pyroscope["Pyroscope"]
            MinIO["MinIO"]
            AlertMgr["AlertManager"]
            MailHog["MailHog"]
            KSM["kube-state-metrics\n(ns: ksm)"]
        end

        subgraph NS_VAULT["Namespace: vault"]
            Vault["Vault\n(dev mode)"]
            ESO["External Secrets\nOperator"]
        end
    end

    Browser --> Ingress
    Ingress --> App
    Ingress --> Grafana
    Ingress --> AlertMgr
    Ingress --> MailHog
    Ingress --> MinIO

    App --> MySQL
    App --> OTel

    ESO --> Vault
    ESO --> App
    ESO --> MySQL

    OTel --> Tempo
    OTel --> Mimir
    OTel --> Loki

    Grafana --> Loki
    Grafana --> Tempo
    Grafana --> Mimir
    Grafana --> Pyroscope

    App --> Pyroscope

    Mimir --> AlertMgr
    AlertMgr --> MailHog
```

---

## 2. Fluxo de Observabilidade

```mermaid
flowchart LR
    App["inventory-app\n(Go)"]

    subgraph OTEL["OTel Collector"]
        R_OTLP["receiver:\notlp/grpc :4317\notlp/http :4318"]
        R_PROM["receiver:\nprometheus scrape"]
        P_BATCH["processor:\nbatch"]
        E_TEMPO["exporter:\notlp → Tempo"]
        E_MIMIR["exporter:\nprometheusremotewrite\n→ Mimir"]
        E_LOKI["exporter:\nloki → Loki"]
    end

    subgraph METRICS["Métricas"]
        Mimir["Mimir\n(long-term storage)"]
        KSM["kube-state-metrics"]
    end

    subgraph LOGS["Logs"]
        Loki["Loki"]
    end

    subgraph TRACES["Traces"]
        Tempo["Tempo"]
    end

    subgraph PROFILING["Profiling"]
        Pyroscope["Pyroscope"]
    end

    Grafana["Grafana\n(dashboards)"]
    AlertMgr["AlertManager"]

    App -->|"OTLP gRPC\n(metrics+logs+traces)"| R_OTLP
    App -->|"pprof endpoint"| Pyroscope

    R_OTLP --> P_BATCH
    R_PROM --> P_BATCH
    P_BATCH --> E_TEMPO
    P_BATCH --> E_MIMIR
    P_BATCH --> E_LOKI

    E_TEMPO --> Tempo
    E_MIMIR --> Mimir
    E_LOKI --> Loki
    Alloy -->|remote_write| Mimir

    Grafana -->|query| Loki
    Grafana -->|query| Tempo
    Grafana -->|query| Mimir
    Grafana -->|query| Pyroscope

    Mimir -->|rules/alerts| AlertMgr
```

---

## 3. Fluxo de Secrets (Vault → Pod)

```mermaid
sequenceDiagram
    participant TF as Terraform
    participant Vault as Vault (dev mode)
    participant ESO as External Secrets Operator
    participant K8s as Kubernetes Secret
    participant Pod as Pod (inventory-app / mysql)

    TF->>Vault: enable KV v2 + write secrets\n(mysql_password, minio_password)
    TF->>ESO: apply ClusterSecretStore\n(aponta para Vault)
    TF->>ESO: apply ExternalSecret\n(mysql-secret, minio-secret)
    ESO->>Vault: GET /secret/data/inventory
    Vault-->>ESO: { db_password: "..." }
    ESO->>K8s: create/update Secret
    K8s-->>Pod: mount as env var\n(DB_PASSWORD)
```

---

## 4. Estrutura Terraform — Módulos

```mermaid
graph TD
    ROOT["root module\nmain.tf"]

    ROOT -->|"depends_on"| NS["kubernetes_namespace\napi-app-go"]
    ROOT --> MOD_VAULT["module: vault\n(Vault + init secrets)"]
    ROOT --> MOD_ESO["module: external-secrets\n(ESO + ClusterSecretStore)"]
    ROOT --> MOD_ALERT["module: alertmanager\n(AlertManager + MailHog)"]
    ROOT --> MOD_APP["module: app\n(helm_release principal + KSM)"]

    MOD_ESO -->|depends_on| MOD_VAULT
    MOD_ESO -->|depends_on| NS
    MOD_APP -->|depends_on| MOD_ESO
    MOD_APP -->|depends_on| MOD_ALERT

    subgraph APP_DETAIL["module: app — helm_release"]
        CHART["helm-chart/\n(chart próprio)"]
        HASH["SHA256 de todos\nos arquivos do chart\n→ auto-upgrade on change"]
    end

    MOD_APP --> APP_DETAIL
```

---

## 5. Infraestrutura Kind — Nodes e Networking

```mermaid
graph LR
    subgraph Kind_Network["Docker Network: kind"]
        CP["control-plane\n(172.18.0.x)"]
        W1["worker-1\n(172.18.0.x)"]
        W2["worker-2\n(172.18.0.x)"]
    end

    subgraph Host["Host Machine"]
        Docker["Docker Engine"]
        KubeConfig["~/.kube/config"]
        Ports["localhost:80 / :443\n→ Nginx Ingress"]
    end

    Docker --> CP
    Docker --> W1
    Docker --> W2
    CP <--> W1
    CP <--> W2
    Ports -->|portMapping| W1
    KubeConfig --> CP
```
