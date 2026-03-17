# Erros e seus tratamentos

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