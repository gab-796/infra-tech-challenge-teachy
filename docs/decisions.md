# Decisões de arquitetura

## HPA — Scaling real bloqueado por PVC ReadWriteOnce no Kind

**Causa raiz:** grafana, loki, tempo, pyroscope e mimir usam PVCs com `accessMode: ReadWriteOnce` (RWO). Um volume RWO só pode ser montado por **um pod em um único nó** ao mesmo tempo. Quando o HPA tenta criar um segundo pod, o Kubernetes não consegue montar o mesmo PVC e o pod fica preso em `Pending` com:
```
0/3 nodes are available: 3 node(s) had volume node affinity conflict
```

O StorageClass `standard` do Kind (`rancher.io/local-path`) **não suporta ReadWriteMany (RWM)**. Suporte a RWM exige um provisioner externo (NFS, CephFS, EFS).

**Componentes com HPA desabilitado (PVC RWO):** grafana, tempo, pyroscope, mysql

**Componentes com HPA ativo:** inventory-app, loki, mimir

**Para habilitar RWM e scaling real nos demais componentes:**
1. Instalar provisioner NFS no Kind (ex: `nfs-subdir-external-provisioner`)
2. Criar StorageClass com suporte a `ReadWriteMany`
3. Mudar `persistence.accessMode: ReadWriteMany` no `values.yaml`
4. Setar `autoscaling.enabled: true` nos componentes desejados

---

## Loki — Migração de filesystem para MinIO (habilita HPA)

**Problema:** Loki com `storage: filesystem` salva todos os chunks, índices e rules no PVC `/loki`. Com RWO, o segundo pod não consegue montar o mesmo volume e fica Pending. Além disso, com filesystem cada pod teria sua própria cópia dos dados, gerando inconsistência.

**Solução adotada:** Migrar o storage do Loki para MinIO (S3-compatible), o mesmo backend já usado pelo Mimir. Com isso:
- Storage de chunks e índices vai para o bucket `loki-chunks` no MinIO
- O pod não precisa mais de PVC para dados (usa `emptyDir` apenas para arquivos temporários)
- Qualquer pod do Loki lê e escreve no mesmo bucket → stateless real
- PVC `loki-pvc` removido quando `minio.enabled: true` (condicional no template)

**Schema atualizado:** `tsdb v13` (schema moderno recomendado para object storage) em vez de `boltdb-shipper v11` (filesystem only).

**initContainer:** O Deployment do Loki usa o mesmo padrão do Mimir — um initContainer com `minio/mc` que cria o bucket `loki-chunks` automaticamente antes de o pod subir.

**Memberlist para scaling real:** Com `kvstore: inmemory`, cada réplica do Loki teria seu próprio anel isolado — o Service faria load-balance entre pods que não se enxergam, causando split de dados e containers sumindo nas queries. A solução foi migrar para `kvstore: store: memberlist` + um Headless Service (`clusterIP: None`) na porta 7946 para peer discovery. Com isso os pods se descobrem e coordenam o anel distribuído, permitindo `maxReplicas: 2` sem inconsistência.

### Solução idêntica para o Mimir
**Memberlist para scaling real:** Com `kvstore: inmemory`, cada réplica do Mimir tem seu próprio anel isolado — ingester, distributor, store_gateway, compactor e ruler cada um com seu estado local.
O Service fazia load-balance entre pods que não se enxergavam, causando inconsistência nas queries (métricas aparecendo ou sumindo dependendo de qual pod respondia).
A solução foi migrar todos os 5 rings para `kvstore: store: memberlist` + bloco `memberlist.join_members` apontando para `mimir-headless:7946` + Headless Service (`clusterIP: None`) para peer discovery.
Com isso os pods formam um cluster coordenado e qualquer pod consegue responder qualquer query com consistência.

---

## Mimir WAL — emptyDir em vez de PVC (habilita HPA)

**Contexto:** O Mimir já usava MinIO para os blocos de métricas (`blocks_storage: backend: s3`). O PVC `/data` servia apenas como WAL (Write-Ahead Log) — um buffer local e transitório antes do flush para o MinIO.

**Solução adotada:** Substituir o PVC `mimir-pvc` por `emptyDir: {}` no volume `mimir-storage`.

**Trade-off aceito:** Se o pod crashar, as métricas ainda não flushed para o MinIO (escritas no WAL nos últimos segundos/minutos) são perdidas. Os dados duradouros ficam seguros no MinIO.

**Por que é aceitável em dev/challenge:**
- A janela de perda é pequena (segundos antes do próximo flush)
- Não há análise crítica de métricas históricas nesse ambiente
- Em produção, isso seria resolvido com `replication_factor: 3` (3 ingesters recebem a mesma métrica)

**Nota:** WAL em S3/MinIO não é suportado pelo Mimir — o WAL precisa de I/O POSIX local de alta velocidade. `emptyDir` é a alternativa correta.

---

## AlertManager PVC/PV fantasma após terraform destroy

**Sintoma:** Após `terraform destroy`, o PVC `storage-alertmanager-0` some mas o PV fica em estado `Released` ou `Bound` sem PVC. No próximo `terraform apply`, o pod do alertmanager não sobe com o erro:
```
Bound claim has lost its PersistentVolume. Data on the volume is lost!
```
ou
```
persistentvolumeclaim "storage-alertmanager-0" bound to non-existent persistentvolume "pvc-xxxx"
```

**Causa raiz:** O alertmanager usa um **StatefulSet com `volumeClaimTemplates`**. O Kubernetes deliberadamente **nunca deleta** PVCs criados por `volumeClaimTemplates` ao remover um StatefulSet — comportamento intencional para proteger dados. O Terraform destrói o Helm release, o StatefulSet some, mas o PVC (e o PV) ficam órfãos.

Todos os outros componentes (grafana, loki, mimir, etc.) usam Deployment com PVCs declarados diretamente no template Helm — esses são gerenciados pelo Helm e deletados normalmente no uninstall.

**Solução adotada:** Persistência desabilitada no alertmanager (`persistence.enabled: false`). Em ambiente local/dev o alertmanager não precisa persistir dados — as regras vêm do Mimir e o histórico de silences/notificações é descartável.

**Solução manual se o problema voltar:**
```bash
kubectl delete pvc storage-alertmanager-0 -n monitoring --ignore-not-found=true
kubectl get pv | grep alertmanager  # se sobrar PV
kubectl delete pv <nome-do-pv>
```

---

## Network Policy — Habilitada e funcional

A `NetworkPolicy` está implementada e funcionando no projeto (`helm-chart/templates/network-policy.yaml`). O Cilium (CNI utilizado no cluster Kind) suporta `NetworkPolicy` nativamente, e as políticas foram validadas com a stack completa em execução.

**Políticas implementadas:**
- Isolamento por namespace: pods do namespace `api-app-go` só aceitam tráfego de dentro do mesmo namespace e do ingress controller
- Cada componente tem regras de ingress/egress específicas para os serviços com os quais precisa se comunicar
- O toggle `networkPolicy.enabled` no `values.yaml` permite desabilitar temporariamente em caso de troubleshooting

> **Atenção:** Desabilitar a NetworkPolicy (`networkPolicy.enabled: false`) abre o tráfego entre todos os pods do namespace. Recomendado manter habilitado em qualquer ambiente.

---

## Alloy — Não é necessário para profiling

O Alloy **não é necessário para coleta de profiling**. A `inventory-app` envia dados de profiling diretamente para o Pyroscope via SDK, usando a variável de ambiente `PYROSCOPE_URL: http://pyroscope:4040`. Não há intermediário nesse fluxo.

```
inventory-app
    └── SDK Pyroscope → Pyroscope (direto, sem Alloy)
```

O Alloy existe nesta stack exclusivamente para **sincronização de regras de alerta** com o Mimir ruler (via `mimir.rules.kubernetes`). Ele lê os `PrometheusRule` ConfigMaps do cluster e os aplica automaticamente ao Mimir, mantendo as regras versionadas em código (GitOps de alertas).

Se o objetivo for apenas profiling, o Alloy pode ser desabilitado sem impacto nenhum na coleta de dados do Pyroscope.

---

## Vault em dev mode — por que não tem PVC?

O Vault está rodando em **dev mode** (`server.dev.enabled: true`), que é um modo especial do Vault para desenvolvimento local. Nesse modo, o Vault:

- Inicializa já unsealed e pronto automaticamente (sem processo de init/unseal)
- Armazena tudo **em memória** — sem backend de storage persistente
- Usa um root token fixo definido em `var.vault_root_token`

Por isso não há PVC: não existe nada para persistir — todos os dados vivem na memória do pod e são recriados pelo `null_resource.vault_init` a cada `terraform apply`.

**Por que não sair do dev mode?**

Sair do dev mode exigiria configurar um backend de storage real (ex: `raft` integrado ou um banco externo), além de:

- **Init**: gerar as unseal keys e o root token inicial (processo único e manual)
- **Unseal**: a cada restart do pod, o Vault inicia *sealed* e precisa de 3 das 5 unseal keys (ou auto-unseal via KMS/Transit) para ser desbloqueado
- **HA**: configurar raft com múltiplos pods para não ter single point of failure
- **Renovação de tokens/leases**: gerenciar TTLs e renovação dos secrets

Para um ambiente local de desenvolvimento e demonstração, o dev mode é suficiente e mantém a stack simples. Em produção, usaria um Vault gerenciado (HCP Vault, AWS Secrets Manager, etc.) em vez de self-hosted dev mode.

---

## Resumo das Decisões de Design e Trade-offs

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

# Troubleshooting


## Caso algum container apresente o erro too many open files

Para o Fedora:

```
sudo nano /etc/sysctl.d/99-inotify.conf
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=2048

sudo sysctl --system
```

Nota: Essas configs já nascem com o cluster kind, mas podem se perder por reinicio de VM ou host.
Já está com a persistencia la, mas vai que...