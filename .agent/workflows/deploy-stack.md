---
description: como fazer deploy ou re-deploy da stack de observabilidade (Kind + app)
---

## Pré-condições

1. Confirmar credenciais exportadas no terminal:
   ```bash
   echo $TF_VAR_mysql_root_password
   echo $MINIO_ROOT_USER
   echo $MINIO_ROOT_PASSWORD
   echo $TF_VAR_minio_root_password
   ```
   Se alguma estiver vazia, instruir o usuário a exportá-las antes de continuar.

2. Confirmar se o MinIO state backend está rodando:
   ```bash
   docker ps | grep minio-state
   ```
   Se não estiver: o `setup-all.sh` vai inicializá-lo automaticamente.

3. Confirmar se o cluster Kind existe (para opção 3 apenas):
   ```bash
   kind get clusters
   ```

## Deploy completo (cluster + app)

Use quando nenhum cluster existir ou quiser recriar tudo do zero:

```bash
bash setup-all.sh
# escolher opção 1
```

## Re-deploy apenas da app (cluster já existe)

Use quando quiser aplicar mudanças no Terraform/Helm sem recriar o cluster:

```bash
bash setup-all.sh
# escolher opção 3
```

Ou manualmente:
```bash
terraform init \
  -backend-config="access_key=$MINIO_ROOT_USER" \
  -backend-config="secret_key=$MINIO_ROOT_PASSWORD" \
  -migrate-state -force-copy
terraform plan -out=tfplan-app
terraform apply tfplan-app
```

## Ativar ou desativar componentes

Editar `terraform.tfvars` e ajustar as flags booleanas:

```hcl
alertmanager_enabled   = true   # AlertManager + MailHog
vault_enabled          = true   # HashiCorp Vault
eso_enabled            = true   # External Secrets Operator
grafana_enabled        = true
loki_enabled           = true
tempo_enabled          = true
mimir_enabled          = true
pyroscope_enabled      = true
alloy_enabled          = true
otel_collector_enabled = true
```

Depois re-aplicar:
```bash
terraform apply tfplan-app
```

## Status pós-deploy

```bash
bash setup-all.sh
# escolher opção 4
```

Ou manualmente:
```bash
kubectl get pods -n api-app-go
kubectl get pods -n vault
kubectl get pods -n alertmanager
kubectl get ingress -n api-app-go
helm list -n api-app-go
```

## Destruir

- **Só a app** (mantém o cluster Kind): `bash setup-all.sh` → opção 5
- **Tudo** (app + cluster + MinIO state): `bash setup-all.sh` → opção 6
