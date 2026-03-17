# Erros e seus tratamentos

## HPA — Scaling real bloqueado por PVC ReadWriteOnce no Kind

**Causa raiz:** grafana, loki, tempo, pyroscope, alloy e mimir usam PVCs com `accessMode: ReadWriteOnce` (RWO). Um volume RWO só pode ser montado por **um pod em um único nó** ao mesmo tempo. Quando o HPA tenta criar um segundo pod, o Kubernetes não consegue montar o mesmo PVC e o pod fica preso em `Pending` com:
```
0/3 nodes are available: 3 node(s) had volume node affinity conflict
```

O StorageClass `standard` do Kind (`rancher.io/local-path`) **não suporta ReadWriteMany (RWM)**. Suporte a RWM exige um provisioner externo (NFS, CephFS, EFS).

**Componentes com HPA desabilitado (PVC RWO):** grafana, tempo, pyroscope, alloy

**Componentes com HPA ativo:** inventory-app, otel-collector, loki, mimir

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


## Mudança do Alloy pro otel na coleta de logs

Por que DaemonSet?
O filelog lê arquivos em /var/log/pods do node local. Como o cluster tem múltiplos nodes, o OTel precisa rodar em cada node para ler os logs locais — exatamente o que um DaemonSet faz.

O Alloy usava a API do Kubernetes para stream de logs (sem precisar ser DaemonSet), mas o OTel não tem esse mecanismo.

### explicacao
- filelog receiver: lê /var/log/pods/<namespace>_*/*/*.log, detecta formato Docker/CRI-O, extrai namespace, pod_name, container_name do path do arquivo, faz parse de JSON body quando disponível, extrai level

- k8sattributes processor: enriquece com k8s.pod.name, k8s.namespace.name, k8s.deployment.name, k8s.node.name e label service do app

- loki exporter: push para Loki com resource labels namespace, pod, container e attribute level

- Pipeline logs: filelog → k8sattributes, batch → loki

- Deployment → DaemonSet (sem replicas) para ler logs de todos os nodes

- Volume varlogpods montando /var/log/pods do host em readOnly

- ClusterRole: adicionado pods/log

remediando 2
- loki exporter: substituído labels por default_labels_enabled (formato correto)

- Adicionado transform/loki_hints processor: define quais resource attributes (k8s.namespace.name, k8s.pod.name, k8s.container.name) e log attributes (level) viram labels no Loki via o mecanismo de hints

- Pipeline logs: adicionado transform/loki_hints antes do batch

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