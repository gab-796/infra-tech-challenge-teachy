#!/bin/bash
# deploy.sh - Script para fazer deploy via Terraform

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}"

echo "========================================"
echo "Terraform Helm Deployment Script"
echo "========================================"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar pré-requisitos
check_prerequisites() {
    echo "📋 Verificando pré-requisitos..."
    echo ""
    
    # Verificar Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Terraform não está instalado${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Terraform: $(terraform version | head -n 1)"
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl não está instalado${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} kubectl: $(kubectl version --client --short)"
    
    # Verificar Helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}❌ Helm não está instalado${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Helm: $(helm version --short)"
    
    # Verificar conexão com cluster
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Sem conexão com cluster Kubernetes${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Cluster: $(kubectl config current-context)"
    
    echo ""
}

# Inicializar Terraform
init_terraform() {
    echo "🔧 Inicializando Terraform..."
    cd "${TERRAFORM_DIR}"
    terraform init
    echo -e "${GREEN}✓${NC} Terraform inicializado"
    echo ""
}

# Validar configuração
validate_terraform() {
    echo "✔️  Validando configuração..."
    cd "${TERRAFORM_DIR}"
    terraform validate
    echo -e "${GREEN}✓${NC} Configuração válida"
    echo ""
}

# Planejar deployment
plan_terraform() {
    echo "📊 Planejando deployment..."
    cd "${TERRAFORM_DIR}"
    terraform plan -out=tfplan
    echo ""
}

# Aplicar deployment
apply_terraform() {
    echo -e "${YELLOW}⚠️  Pronto para fazer o deploy?${NC}"
    read -p "Continuar? (s/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        cd "${TERRAFORM_DIR}"
        terraform apply tfplan
        echo -e "${GREEN}✓${NC} Deployment concluído!"
        echo ""
    else
        echo "Deploy cancelado"
        exit 0
    fi
}

# Mostrar status
show_status() {
    echo "📊 Status do Deployment:"
    echo ""
    
    echo "Helm Releases:"
    helm list -A | grep -E "api-observabilidade|NAME"
    echo ""
    
    echo "Pods:"
    kubectl get pods -n api-app-go
    echo ""
    
    echo "Serviços:"
    kubectl get svc -n api-app-go
    echo ""
    
    echo "Ingress:"
    kubectl get ingress -n api-app-go
    echo ""
}

# Menu principal
main() {
    case "${1:-}" in
        "init")
            check_prerequisites
            init_terraform
            ;;
        "plan")
            check_prerequisites
            init_terraform
            validate_terraform
            plan_terraform
            ;;
        "apply")
            check_prerequisites
            init_terraform
            validate_terraform
            plan_terraform
            apply_terraform
            show_status
            ;;
        "deploy")
            check_prerequisites
            init_terraform
            validate_terraform
            plan_terraform
            apply_terraform
            show_status
            ;;
        "status")
            show_status
            ;;
        "destroy")
            echo -e "${RED}⚠️  Isso vai destruir todos os recursos!${NC}"
            read -p "Tem certeza? (s/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Ss]$ ]]; then
                cd "${TERRAFORM_DIR}"
                terraform destroy
            fi
            ;;
        "validate")
            check_prerequisites
            validate_terraform
            ;;
        *)
            echo "Uso: $0 {init|plan|apply|deploy|status|destroy|validate}"
            echo ""
            echo "Comandos:"
            echo "  init       - Inicializar Terraform"
            echo "  validate   - Validar configuração"
            echo "  plan       - Planejar deployment"
            echo "  apply      - Aplicar deployment (plan + apply)"
            echo "  deploy     - Deploy completo (init + plan + apply + status)"
            echo "  status     - Mostrar status do deployment"
            echo "  destroy    - Destruir todos os recursos"
            exit 1
            ;;
    esac
}

main "$@"
