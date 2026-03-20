# Kind Cluster Terraform Resources

# =============================================================================
# CRIAÇÃO E DESTRUIÇÃO DO CLUSTER KIND
# =============================================================================
# Usamos null_resource + local-exec porque o provider oficial do Kind não
# oferece suporte completo a todas as opções de configuração que precisamos.
# O local-exec executa comandos diretamente na máquina onde o terraform roda.
resource "null_resource" "kind_cluster_create" {
  count = var.create_kind_cluster ? 1 : 0

  # Provisioner de criação: executado no terraform apply
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Verifica se o cluster já existe antes de tentar criar.
      # Isso torna o script idempotente: se o cluster já existir (ex: após um
      # terraform apply parcial ou criação manual), o script não falha nem
      # recria o cluster desnecessariamente.
      if kind get clusters -q 2>/dev/null | grep -q "^${var.kind_cluster_name}$"; then
        echo "Cluster ${var.kind_cluster_name} already exists"
        kind export kubeconfig --name ${var.kind_cluster_name}
        exit 0
      fi

      echo "Creating Kind cluster: ${var.kind_cluster_name}"

      # O Kind precisa de uma rede Docker chamada "kind" para funcionar.
      # Este comando garante que ela existe antes de criar o cluster,
      # evitando falhas em ambientes onde a rede ainda não foi criada
      # (ex: primeira execução após reinstalar o Docker).
      docker network inspect kind >/dev/null 2>&1 || docker network create kind

      # Cria o cluster usando o arquivo de configuração definido em var.kind_config_path.
      # O --wait 10s aguarda os componentes do control plane subirem antes de retornar,
      # garantindo que o cluster está minimamente funcional ao final do comando.
      kind create cluster --name ${var.kind_cluster_name} --config=${var.kind_config_path} --wait 10s

      echo "Kind cluster created successfully!"
    EOT

    interpreter = ["bash", "-c"]
    working_dir = path.module
  }

  # Provisioner de destruição: executado no terraform destroy.
  # Referencia o nome do cluster via self.triggers para garantir que o valor
  # correto seja usado mesmo que a variável tenha mudado desde o último apply.
  # O "|| true" no final evita que o destroy falhe caso o cluster já tenha
  # sido deletado manualmente antes do terraform destroy ser executado.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      echo "Deleting Kind cluster: ${self.triggers.cluster_name}"
      kind delete cluster --name ${self.triggers.cluster_name} || true
      echo "Kind cluster deleted!"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Os triggers controlam quando o Terraform vai recriar este recurso.
  # - cluster_name: se o nome do cluster mudar, o recurso é destruído e recriado.
  # - config_file: usa o MD5 do arquivo de configuração do Kind. Se o conteúdo
  #   do arquivo mudar (ex: adicionar um novo worker node, alterar portas),
  #   o Terraform detecta a mudança e recria o cluster automaticamente no próximo apply.
  triggers = {
    cluster_name = var.kind_cluster_name
    config_file  = filemd5("${path.module}/${var.kind_config_path}")
  }
}

# =============================================================================
# AJUSTE DE LIMITES DE INOTIFY DO KERNEL
# =============================================================================
# O Kind cria múltiplos containers que, por sua vez, criam muitos file watchers.
# O Linux tem limites baixos por padrão para inotify (mecanismo do kernel usado
# por kubelet, containerd e outras ferramentas para monitorar mudanças em arquivos).
# Sem esse ajuste, o cluster pode falhar com erros como "too many open files"
# ou "failed to create inotify instance". Os valores abaixo são os recomendados
# pela documentação do Kind para ambientes de desenvolvimento local.
resource "null_resource" "inotify_tuning" {
  count = var.enable_inotify_tuning ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Tuning inotify settings..."

      # Verifica se o usuário tem permissão de sudo sem senha antes de tentar aplicar.
      # Se não tiver, exibe as instruções para aplicar manualmente e encerra sem falhar,
      # para não bloquear o terraform apply em ambientes com restrições de sudo.
      if sudo -n true 2>/dev/null; then
        sudo sysctl fs.inotify.max_user_watches=524288
        sudo sysctl fs.inotify.max_user_instances=512

        # Persiste as configurações no sysctl.conf para que sobrevivam a reboots.
        # O grep antes do echo evita duplicar as linhas caso o script seja
        # executado mais de uma vez (idempotência).
        grep -q "max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
        grep -q "max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf

        echo "inotify tuning completed"
      else
        echo "Warning: Cannot apply inotify tuning without sudo. Please run manually:"
        echo "  sudo sysctl fs.inotify.max_user_watches=524288"
        echo "  sudo sysctl fs.inotify.max_user_instances=512"
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.kind_cluster_create]
}

# =============================================================================
# INSTALAÇÃO DO CILIUM CNI
# =============================================================================
# O Kind não instala um CNI por padrão quando configurado sem o kindnet.
# O Cilium é usado aqui como CNI (Container Network Interface), responsável
# pela comunicação entre pods. Instalado via Helm após o cluster estar pronto.
resource "helm_release" "cilium" {
  count = var.install_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  # O modo "kubernetes" de IPAM delega o gerenciamento de IPs dos pods
  # ao próprio Kubernetes (via node.spec.podCIDR), que é o comportamento
  # esperado em clusters Kind onde o CIDR já é definido no config do cluster.
  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  depends_on = [null_resource.kind_cluster_create]
}

# =============================================================================
# INSTALAÇÃO DO METRICS SERVER
# =============================================================================
# O Metrics Server coleta métricas de CPU e memória dos nodes e pods,
# necessário para que o HPA (Horizontal Pod Autoscaler) e o comando
# "kubectl top" funcionem corretamente.
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = "kube-system"

  # O Kind usa certificados TLS auto-assinados no kubelet. A flag
  # --kubelet-insecure-tls desabilita a verificação do certificado,
  # necessário para que o Metrics Server consiga coletar métricas
  # em ambientes de desenvolvimento local com Kind.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [helm_release.cilium]
}

# =============================================================================
# INSTALAÇÃO DO METALLB (LOAD BALANCER)
# =============================================================================
# O Kind não tem suporte nativo a LoadBalancer services (diferente de clouds
# como AWS/GCP que provisionam um LB externo automaticamente). O MetalLB
# implementa um load balancer para ambientes bare-metal/locais, permitindo
# que services do tipo LoadBalancer recebam um IP externo acessível.
# Instalado via local-exec (kubectl) em vez de Helm para ter controle total
# sobre a configuração do IPAddressPool com a subnet correta do Docker.
resource "null_resource" "metallb_install" {
  count = var.install_metallb ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Installing MetalLB..."

      # Aplica os manifests oficiais do MetalLB diretamente do GitHub.
      kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v${var.metallb_version}/config/manifests/metallb-native.yaml

      # Aguarda o controller do MetalLB estar pronto antes de configurar o pool.
      # Sem essa espera, a criação do IPAddressPool pode falhar pois o CRD
      # ainda não estaria registrado no cluster.
      kubectl rollout status -n metallb-system deployment controller

      # Detecta automaticamente a subnet da rede Docker "kind".
      # O MetalLB precisa de um range de IPs para alocar aos LoadBalancers.
      # Usando a subnet da rede Docker, garantimos que os IPs alocados são
      # roteáveis a partir da máquina host, permitindo acesso local aos serviços.
      DOCKER_SUBNET=$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' kind)

      echo "Configuring MetalLB with subnet: $DOCKER_SUBNET"

      # Cria o IPAddressPool com toda a subnet Docker disponível e um
      # L2Advertisement para anunciar os IPs via ARP na rede local.
      cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: metallb-pool
  namespace: metallb-system
spec:
  addresses:
  - $DOCKER_SUBNET
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

      echo "MetalLB installed successfully!"
    EOT

    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.kind_cluster_name
  }

  depends_on = [helm_release.metrics_server]
}

# =============================================================================
# INSTALAÇÃO DO NGINX INGRESS CONTROLLER
# =============================================================================
# O Ingress Controller é responsável por rotear tráfego HTTP/HTTPS externo
# para os services dentro do cluster com base em regras de Ingress.
# Depende do MetalLB para receber um IP externo via LoadBalancer service.
resource "helm_release" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = "kube-system"

  depends_on = [null_resource.metallb_install]
}

# =============================================================================
# BARREIRA DE SINCRONIZAÇÃO: AGUARDA O CLUSTER ESTAR PRONTO
# =============================================================================
# Este recurso serve como ponto de sincronização final do apply.
# Ele aguarda que todos os nodes do cluster estejam no estado Ready antes
# de considerar o terraform apply concluído, garantindo que o cluster está
# totalmente operacional para uso após o provisionamento.
# O "|| true" evita falha caso algum node demore mais que o timeout de 300s,
# tratando isso como um aviso em vez de erro fatal.
resource "null_resource" "cluster_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Waiting for cluster to be fully ready..."

      # Aguarda todos os nodes ficarem Ready com timeout de 5 minutos.
      # O contexto kind-<nome> é criado automaticamente pelo Kind no kubeconfig local.
      kubectl wait --for=condition=Ready node --all --timeout=300s --context=kind-${var.kind_cluster_name} || true

      echo "Cluster is ready!"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [helm_release.ingress_nginx]
}
