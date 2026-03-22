---
description: como criar e integrar um novo módulo Terraform nesse projeto
---

## Estrutura de um módulo

```
modules/<nome>/
  main.tf       # recursos principais
  variables.tf  # inputs do módulo
  outputs.tf    # outputs expostos ao root
```

## Passos

### 1. Criar os arquivos do módulo

Criar `modules/<nome>/variables.tf` com todas as variáveis de input:
```hcl
variable "<nome>_enabled" {
  description = "Install <nome>"
  type        = bool
  default     = false
}

variable "<nome>_version" {
  description = "<Nome> Helm chart version"
  type        = string
  default     = "x.y.z"
}
```

Criar `modules/<nome>/main.tf` com os recursos. Usar `count` para habilitação condicional:
```hcl
resource "helm_release" "<nome>" {
  count      = var.<nome>_enabled ? 1 : 0
  name       = "<nome>"
  repository = "https://..."
  chart      = "<chart>"
  version    = var.<nome>_version
  namespace  = var.namespace
  ...
}
```

Criar `modules/<nome>/outputs.tf` expondo o que outros módulos precisam:
```hcl
output "<nome>_url" {
  value = var.<nome>_enabled ? "http://<nome>.local" : ""
}
```

### 2. Integrar no root

Em `variables.tf` (root), adicionar as variáveis novas correspondentes.

Em `main.tf` (root), declarar o módulo e suas dependências:
```hcl
module "<nome>" {
  source = "./modules/<nome>"

  <nome>_enabled = var.<nome>_enabled
  <nome>_version = var.<nome>_version
  namespace      = var.namespace

  depends_on = [kubernetes_namespace.app_namespace]
}
```

Se outros módulos dependem deste: adicionar `module.<nome>` no `depends_on` deles.

Se este módulo expõe URL para o módulo `app`: passar via `<nome>_url = module.<nome>.<nome>_url`.

### 3. Adicionar defaults em terraform.tfvars

```hcl
<nome>_enabled = false
<nome>_version = "x.y.z"
```

### 4. Se o componente entra no Helm chart

Adicionar em `helm-chart/infra-tech-challenge-teachy/`:
- Template(s) em `templates/<nome>/`
- Seção no `values.yaml`:
  ```yaml
  <nome>:
    enabled: false
    image:
      tag: "x.y.z"
  ```

O módulo `app` detecta mudanças no chart via SHA256 → `helm upgrade` automático no próximo `terraform apply`.

## Padrão de habilitação condicional (resumo)

- Recursos: `count = var.<nome>_enabled ? 1 : 0`
- Outputs com fallback: `value = var.<nome>_enabled ? "<valor real>" : ""`
- Nunca usar `for_each` para habilitação condicional simples — `count` é mais previsível

## Dependências já estabelecidas (não quebrar)

```
kubernetes_namespace (root)
  └── module.vault
        └── module.external_secrets
              └── module.app ← também depende de module.alertmanager
  └── module.alertmanager
```
