# Como as secrets são criadas e consumidas

## Fluxo completo

```
export TF_VAR_mysql_root_password="suasenha-1"
export TF_VAR_minio_root_password="suasenha-2"
         │
         ▼
    modules/vault/main.tf
    null_resource.vault_init
    → vault kv put secret/inventory
        DB_PASSWORD=<mysql_root_password>
        MYSQL_ROOT_PASSWORD=<mysql_root_password>
        MINIO_ROOT_PASSWORD=<minio_root_password>
         │
         ▼
    modules/external-secrets/main.tf
    kubernetes_secret.vault_token
    → cria k8s secret "vault-token" com o root token do Vault
    (garante que o token existe antes do ESO tentar autenticar)
         │
         ▼
    null_resource.setup_external_secrets
    → aplica ClusterSecretStore (aponta para Vault, usa vault-token)
    → aplica 3 ExternalSecrets:
        • mysql-external-secret     → k8s secret "mysql-secrets"
        • inventory-app-external-secret → k8s secret "inventory-app-secrets"
        • minio-external-secret     → k8s secret "minio-secrets"
    → aguarda os 3 secrets existirem antes de continuar
         │
         ├──▶ mysql.yaml
         │      env MYSQL_ROOT_PASSWORD ← secretKeyRef: mysql-secrets/MYSQL_ROOT_PASSWORD
         │
         ├──▶ inventory-app.yaml
         │      env DB_PASSWORD ← secretKeyRef: inventory-app-secrets/DB_PASSWORD
         │      (nome do secret: "inventory-app-secrets", não "inventory-app-secrets")
         │
         └──▶ minio.yaml
                env MINIO_ROOT_PASSWORD ← secretKeyRef: minio-secrets/MINIO_ROOT_PASSWORD
                env MINIO_ROOT_USER     ← value: "minio" (hardcoded no values.yaml)
```

> **Nota:** O `inventory-app.yaml` referencia o secret como `{{ .Values.inventoryApp.name }}-secrets`, que resolve para `inventory-app-secrets`. Isso bate exatamente com o `target.name` do ExternalSecret `inventory-app-external-secret`.

---

## Senhas MySQL — uma variável, dois usos

Os dois secrets (`DB_PASSWORD` para a app e `MYSQL_ROOT_PASSWORD` para o MySQL) vêm do mesmo `TF_VAR_mysql_root_password`. Uma variável só resolve os dois.

> **Boa prática não implementada:** O ideal seria separar — `MYSQL_ROOT_PASSWORD` para o root do MySQL e `DB_PASSWORD` para um usuário com permissões limitadas (SELECT, INSERT, etc.). Isso é o princípio de least privilege. A app nunca deveria ter acesso root ao banco. Para este ambiente de desenvolvimento, o acesso root foi mantido por simplicidade.

---

## MinIO — dois contextos diferentes

| Contexto | Variável | Onde é usada |
|---|---|---|
| MinIO state backend (Docker local) | `MINIO_ROOT_USER` + `MINIO_ROOT_PASSWORD` | `setup-all.sh` para subir o container Docker na porta 9100 |
| MinIO in-cluster (Kubernetes) | `TF_VAR_minio_root_password` | Vault → ESO → `minio-secrets` → pod MinIO |

O usuário do MinIO in-cluster é fixo (`minio`, definido em `values.yaml`). Apenas a senha vem do secret.

---

## O que precisa ser exportado antes do setup

```bash
# Obrigatórias (sem default)
export TF_VAR_mysql_root_password="suasenha"
export MINIO_ROOT_USER="minio"
export MINIO_ROOT_PASSWORD="suasenha"
export TF_VAR_minio_root_password="$MINIO_ROOT_PASSWORD"

# vault_root_token já tem default "root" no terraform.tfvars — não precisa exportar
```

---

## Verificando os secrets no cluster

```bash
# Ver os secrets criados pelo ESO
kubectl get secrets -n api-app-go

# Ver o conteúdo (base64 decode)
kubectl get secret mysql-secrets -n api-app-go -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d
kubectl get secret inventory-app-secrets -n api-app-go -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
kubectl get secret minio-secrets -n api-app-go -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d

# Ver o MinIO state backend (Docker)
# http://localhost:9101 → console web
```
