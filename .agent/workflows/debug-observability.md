---
description: como diagnosticar problemas na stack de observabilidade ou na integração Terraform/Helm
---

## Saúde geral dos pods

```bash
kubectl get pods -n api-app-go        # namespace principal
kubectl get pods -n vault             # Vault + ESO
kubectl get pods -n alertmanager      # AlertManager + MailHog
kubectl get pods -n kube-system       # Cilium, MetalLB, Nginx
```

Para investigar um pod específico:
```bash
kubectl describe pod <pod-name> -n api-app-go
kubectl logs <pod-name> -n api-app-go
kubectl logs <pod-name> -n api-app-go --previous  # crash anterior
```

## Diagnóstico por sinal de observabilidade

### Métricas (App → OTel → Mimir → Grafana)
```bash
# OTel Collector está saudável?
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector -n api-app-go | grep -i "error\|warn\|dropped"

# Mimir está pronto?
curl http://mimir.local/ready

# Grafana consegue consultar o Mimir?
# Acessar http://grafana-web.local → Explore → datasource Mimir → rodar uma query simples
```

### Logs (App → OTel → Loki → Grafana)
```bash
curl http://loki.local/ready
kubectl logs -l app.kubernetes.io/name=loki -n api-app-go | tail -30
```

### Traces (App → OTel gRPC :4317 → Tempo)
```bash
curl http://tempo.local/ready
# No Grafana: Explore → Tempo → buscar por traceID ou por serviço
```

### Profiling (App pprof → Pyroscope)
```bash
curl http://pyroscope.local/ready
# No Grafana: Explore → Pyroscope → selecionar service name
```

### Alertas (Mimir ruler → AlertManager → MailHog)
```bash
curl http://alertmanager.local/-/healthy
curl http://mailhog.local  # inspecionar emails recebidos

# Regras de alerta carregadas no Mimir?
curl http://mimir.local/prometheus/api/v1/rules
```

## Diagnóstico de secrets (Vault → ESO → K8s)

```bash
# ESO está sincronizando?
kubectl get externalsecret -n api-app-go
kubectl describe externalsecret <name> -n api-app-go  # ver status/conditions

# K8s Secret foi criado?
kubectl get secret -n api-app-go

# Vault está acessível e com os secrets?
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-0 -- vault kv get secret/inventory
```

## Diagnóstico de problemas Terraform

```bash
# State lock preso por apply falho anterior
terraform force-unlock <lock-id>

# MinIO state backend inacessível
docker start minio-state
# ou verificar container
docker ps -a | grep minio-state
docker logs minio-state

# Re-inicializar backend
terraform init \
  -backend-config="access_key=$MINIO_ROOT_USER" \
  -backend-config="secret_key=$MINIO_ROOT_PASSWORD" \
  -migrate-state -force-copy
```

## Problemas comuns e soluções

| Sintoma | Causa provável | Solução |
|---|---|---|
| Pod em `CrashLoopBackOff` | Secret não sincronizado (ESO) | Verificar `kubectl describe externalsecret` |
| Grafana sem dados em datasource | URL de datasource errada | Checar datasource no Grafana UI → Test |
| OTel não recebe traces/logs | App apontando para endpoint errado | Verificar env `OTEL_EXPORTER_OTLP_ENDPOINT` no pod |
| `terraform apply` trava em Helm | Pods não sobem (CrashLoop) | Verificar logs dos pods problemáticos |
| State lock preso | Apply anterior falhou ou abortado | `terraform force-unlock <id>` |
| MinIO inacessível | Container Docker parado | `docker start minio-state` |
| Ingress não responde | `/etc/hosts` desatualizado | Verificar IP do MetalLB e atualizar hosts |

## Reiniciar um componente

```bash
kubectl rollout restart deployment/<nome> -n api-app-go
kubectl rollout status deployment/<nome> -n api-app-go
```

## Ver eventos do namespace (útil para problemas de scheduling/PVC)

```bash
kubectl get events -n api-app-go --sort-by=.lastTimestamp | tail -20
```
