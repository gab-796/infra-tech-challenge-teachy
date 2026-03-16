# Como as secrets são criadas

```
export TF_VAR_mysql_root_password="qualquer_valor"
         │
         ▼
    Terraform (main.tf)
    vault kv put secret/inventory
      DB_PASSWORD=qualquer_valor
      MYSQL_ROOT_PASSWORD=qualquer_valor
         │
         ▼
    Vault (secret/inventory)
         │
         ▼
    ESO (ExternalSecret)
    lê do Vault e cria dois K8s Secrets:
      • inventory-app-secrets → chave DB_PASSWORD
      • mysql-secrets         → chave MYSQL_ROOT_PASSWORD
         │
         ├──▶ inventory-app.yaml
         │      env DB_PASSWORD ← secretKeyRef: inventory-app-secrets/DB_PASSWORD
         │
         └──▶ mysql.yaml
                env MYSQL_ROOT_PASSWORD ← secretKeyRef: mysql-secrets/MYSQL_ROOT_PASSWORD
```

## Para configurar secret - Colocar no seu .zshrc

export TF_VAR_mysql_root_password="mysql-senha-supersecreta"
export TF_VAR_minio_root_password="minio-senha-muito-boa"
export MINIO_ROOT_USER="init-minio-root-user"
export MINIO_ROOT_PASSWORD="init-minio-root-pass"

# senhas minio
```
export TF_VAR_minio_root_password="suasenha"
         │
         ▼
    vault kv put secret/inventory
      MINIO_ROOT_PASSWORD=suasenha
         │
         ▼
    ESO → K8s Secret "minio-secrets"
         │
         ├──▶ minio.yaml        → env MINIO_ROOT_PASSWORD (secretKeyRef)
         ├──▶ mimir init container → env MINIO_ROOT_PASSWORD (secretKeyRef) → usado no mc alias set
         └──▶ mimir container   → env MINIO_ROOT_PASSWORD (secretKeyRef) → usado no config ${MINIO_ROOT_PASSWORD}
```

É uma race condition clássica. O pod do MinIO começa antes do ESO ter tempo de sincronizar o ExternalSecret com o Vault e criar o minio-secrets. É a mesma razão pela qual o vault-token é criado diretamente via kubernetes_secret no Terraform — para garantir que existe antes do helm release.

A solução: criar o minio-secrets diretamente via Terraform (como o vault_token), e remover o ExternalSecret do minio do helm chart. O var.minio_root_password já está disponível no Terraform.



## Senhas mysql
Os dois (DB_PASSWORD para a app e MYSQL_ROOT_PASSWORD para o MySQL) vêm do mesmo TF_VAR_mysql_root_password. Uma variável só resolve os dois.


### app usa o acesso root ao bd

Boa prática seria separar. O ideal é:

Secret	Descrição	Usuário MySQL
MYSQL_ROOT_PASSWORD	senha do root	root — só para admin
DB_PASSWORD	senha da aplicação	usuário com permissões limitadas (SELECT, INSERT, etc.)

Isso é o princípio de least privilege — a app nunca deveria ter acesso root ao banco.


## Fluxo de senhas atualizadas

env var (senha)
    ↓
null_resource.vault_init
    → vault kv put secret/inventory ...  (escreve no Vault)
    ↓
kubernetes_secret.vault_token
    → cria k8s secret com o token root do Vault
    ↓
null_resource.setup_external_secrets
    → aplica ClusterSecretStore  (diz ao ESO: "Vault está em X, use esse token")
    → aplica ExternalSecrets     (diz ao ESO: "leia 'inventory' do Vault e crie o k8s secret")
    ↓
ESO sincroniza
    → cria mysql-secrets e inventory-app-secrets no namespace
    ↓
Pods consomem os k8s secrets


### Senhas Minio inicial em docker

env var (MINIO_ROOT_PASSWORD)
         ↓
null_resource.vault_init
  → vault kv put secret/inventory MINIO_ROOT_PASSWORD=...  ← já acontece hoje
         ↓
null_resource.setup_external_secrets
  → ExternalSecret minio-external-secret (a adicionar em manifests/external-secrets.yaml)
         ↓
ESO sincroniza
  → cria minio-secrets k8s secret
         ↓
MinIO pod lê via secretKeyRef → minio-secrets / MINIO_ROOT_PASSWORD


### Verificando o conteudo do minio init
http://localhost:9101 --> via Docker

 MINIO_ROOT_USER e MINIO_ROOT_PASSWORD


### Verificando o conteudo do minio usado pelo Mimir
TF_VAR_minio_root_password
user: minio