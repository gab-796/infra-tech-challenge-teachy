#!/bin/bash
# setup-all.sh - Script para setup completo (Kind + App)

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
KIND_DIR="${PROJECT_ROOT}/kind-cluster"
APP_DIR="${PROJECT_ROOT}"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Complete Terraform Infrastructure    ║${NC}"
echo -e "${BLUE}║  Kind Cluster + Application Deploy    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Função para checar pré-requisitos
check_requirements() {
    echo -e "${YELLOW}📋 Verificando pré-requisitos...${NC}"
    echo ""

    local required_tools=("terraform" "kind" "kubectl" "docker" "helm" "mc")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo -e "${GREEN}✓${NC} $tool: $(eval "$tool" --version 2>&1 | head -n 1)"
        else
            echo -e "${RED}✗${NC} $tool: NOT FOUND"
            missing_tools+=("$tool")
        fi
    done

    echo ""

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}❌ Ferramentas faltando: ${missing_tools[*]}${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Todos os pré-requisitos estão OK!${NC}"
    echo ""
}

# Função para bootstrap do MinIO como state backend
bootstrap_minio_state() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}Bootstrap: MinIO State Backend${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""

    if [ -z "$MINIO_ROOT_USER" ] || [ -z "$MINIO_ROOT_PASSWORD" ]; then
        echo -e "${RED}❌ MINIO_ROOT_USER e MINIO_ROOT_PASSWORD devem estar exportados${NC}"
        exit 1
    fi

    if docker ps --format '{{.Names}}' | grep -q '^minio-state$'; then
        echo -e "${GREEN}✓ minio-state já está rodando${NC}"
    elif docker ps -a --format '{{.Names}}' | grep -q '^minio-state$'; then
        echo -e "${YELLOW}🔄 minio-state existe mas está parado, reiniciando...${NC}"
        docker start minio-state
        sleep 3
    else
        echo -e "${YELLOW}🚀 Iniciando MinIO para state backend...${NC}"
        docker run -d --name minio-state \
            -p 9100:9000 -p 9101:9001 \
            -e MINIO_ROOT_USER \
            -e MINIO_ROOT_PASSWORD \
            -v minio-state-data:/data \
            minio/minio server /data --console-address ":9001"
        sleep 3
    fi

    echo -e "${YELLOW}🪣 Criando bucket tfstate...${NC}"
    mc alias set minio-state http://localhost:9100 \
        "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --insecure 2>/dev/null
    mc mb minio-state/tfstate --ignore-existing
    echo -e "${GREEN}✓ MinIO state backend pronto em http://localhost:9100${NC}"
    echo ""
}

# Função para criar Kind cluster
create_kind_cluster() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}Creating Kind Cluster${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""

    cd "${KIND_DIR}"

    echo -e "${YELLOW}🔧 Inicializando Terraform...${NC}"
    terraform init

    echo -e "${YELLOW}📊 Planejando cluster...${NC}"
    terraform plan -out=tfplan-kind

    echo -e "${YELLOW}🚀 Criando cluster...${NC}"
    terraform apply tfplan-kind

    echo -e "${GREEN}✓ Kind cluster criado!${NC}"
    echo ""

    # Exportar outputs
    echo -e "${YELLOW}📝 Kind Cluster Info:${NC}"
    terraform output cluster_info || true
    echo ""

    cd - > /dev/null
}

# Função para deploy aplicação
deploy_app() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}Deploying Application${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""

    cd "${APP_DIR}"

    echo -e "${YELLOW}🔧 Inicializando Terraform...${NC}"
    terraform init \
        -backend-config="access_key=$MINIO_ROOT_USER" \
        -backend-config="secret_key=$MINIO_ROOT_PASSWORD" \
        -migrate-state

    echo -e "${YELLOW}📊 Planejando deployment...${NC}"
    terraform plan -out=tfplan-app

    echo -e "${YELLOW}🚀 Fazendo deploy...${NC}"
    terraform apply tfplan-app

    echo -e "${GREEN}✓ Aplicação deployada!${NC}"
    echo ""

    cd - > /dev/null
}

# Função para mostrar status
show_status() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}Deployment Status${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""

    echo -e "${YELLOW}🐳 Docker Containers:${NC}"
    docker ps --filter "label=io.x-k8s.kind.cluster" --format "table {{.Names}}\t{{.Status}}"
    echo ""

    echo -e "${YELLOW}📦 Kubernetes Nodes:${NC}"
    kubectl get nodes
    echo ""

    echo -e "${YELLOW}🎯 Namespaces:${NC}"
    kubectl get namespaces | grep api-app-go
    echo ""

    echo -e "${YELLOW}📋 Pods:${NC}"
    kubectl get pods -n api-app-go
    echo ""

    echo -e "${YELLOW}🔌 Services:${NC}"
    kubectl get svc -n api-app-go
    echo ""

    echo -e "${YELLOW}🚦 Ingress:${NC}"
    kubectl get ingress -n api-app-go || echo "Ingress não configurado"
    echo ""

    echo -e "${YELLOW}📦 Helm Releases:${NC}"
    helm list -n api-app-go || echo "Nenhuma release disponível"
    echo ""
}

# Função para menu principal
show_menu() {
    echo -e "${YELLOW}Opções:${NC}"
    echo "1) Criar Kind Cluster + Deploy App (Completo)"
    echo "2) Apenas criar Kind Cluster"
    echo "3) Apenas fazer deploy da App"
    echo "4) Mostrar status"
    echo "5) Destruir apenas a App (manter cluster)"
    echo "6) Destruir tudo"
    echo "7) Sair"
    echo ""
    read -p "Escolha uma opção (1-7): " option
}

# Menu de confirmação
confirm() {
    local prompt="$1"
    read -p "$(echo -e "${YELLOW}${prompt}${NC}") (s/n) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]]
}

# Main
main() {
    check_requirements

    while true; do
        show_menu

        case $option in
            1)
                if confirm "🚀 Criar Kind Cluster + Deploy App?"; then
                    bootstrap_minio_state
                    create_kind_cluster
                    sleep 5
                    deploy_app
                    show_status
                fi
                ;;
            2)
                if confirm "🚀 Criar Kind Cluster?"; then
                    create_kind_cluster
                fi
                ;;
            3)
                if confirm "🚀 Fazer deploy da App?"; then
                    bootstrap_minio_state
                    deploy_app
                fi
                ;;
            4)
                show_status
                ;;
            5)
                if confirm "🗑️  Destruir apenas a App (cluster continua)?"; then
                    bootstrap_minio_state
                    echo -e "${RED}Destruindo aplicação...${NC}"
                    cd "${APP_DIR}"
                    terraform init \
                        -backend-config="access_key=$MINIO_ROOT_USER" \
                        -backend-config="secret_key=$MINIO_ROOT_PASSWORD"
                    terraform destroy -auto-approve
                    cd - > /dev/null
                    echo -e "${GREEN}✓ Aplicação destruída! Cluster continua rodando.${NC}"
                fi
                ;;
            6)
                if confirm "🗑️  Destruir TUDO (Cluster + App)?"; then
                    bootstrap_minio_state
                    echo -e "${RED}Destruindo aplicação...${NC}"
                    cd "${APP_DIR}"
                    terraform init \
                        -backend-config="access_key=$MINIO_ROOT_USER" \
                        -backend-config="secret_key=$MINIO_ROOT_PASSWORD"
                    terraform destroy -auto-approve
                    cd - > /dev/null

                    echo -e "${RED}Destruindo cluster...${NC}"
                    cd "${KIND_DIR}"
                    terraform destroy -auto-approve
                    cd - > /dev/null

                    echo -e "${GREEN}✓ Tudo foi destruído!${NC}"

                    echo -e "${YELLOW}🗑️  Removendo MinIO state backend...${NC}"
                    docker rm -f minio-state 2>/dev/null || true
                    docker volume rm minio-state-data 2>/dev/null || true
                    echo -e "${GREEN}✓ minio-state removido${NC}"
                fi
                ;;
            7)
                echo -e "${GREEN}Saindo...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                ;;
        esac

        echo ""
        read -p "Pressione ENTER para continuar..."
        clear
    done
}

# Executar
main
