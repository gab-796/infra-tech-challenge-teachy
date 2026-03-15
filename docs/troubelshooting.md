# Erros e seus tratamentos

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