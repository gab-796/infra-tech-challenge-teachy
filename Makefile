# Makefile - Terraform Helm Deployment

.PHONY: help init plan apply deploy destroy validate fmt clean status logs

# Cores
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Mostrar esta ajuda
	@echo "$(GREEN)Terraform Helm Deployment - Comandos Disponíveis$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

init: ## Inicializar Terraform
	@echo "$(GREEN)Inicializando Terraform...$(NC)"
	terraform init

validate: ## Validar configuração
	@echo "$(GREEN)Validando configuração...$(NC)"
	terraform validate

fmt: ## Formatar arquivos Terraform
	@echo "$(GREEN)Formatando arquivos...$(NC)"
	terraform fmt -recursive

plan: init validate ## Planejar deployment
	@echo "$(GREEN)Planejando deployment...$(NC)"
	terraform plan -out=tfplan

apply: plan ## Aplicar deployment
	@echo "$(YELLOW)Aplicando deployment...$(NC)"
	terraform apply tfplan
	@echo "$(GREEN)✓ Deployment concluído!$(NC)"

deploy: apply status ## Deploy completo (init + plan + apply + status)
	@echo "$(GREEN)✓ Deploy concluído com sucesso!$(NC)"

destroy: ## Destruir recursos (com confirmação)
	@echo "$(RED)⚠️  Isso vai destruir todos os recursos!$(NC)"
	@read -p "Tem certeza? (s/n) " confirm && [ "$$confirm" = "s" ] && terraform destroy || echo "Cancelado"

destroy-force: ## Destruir recursos sem confirmação
	@echo "$(RED)Destruindo recursos...$(NC)"
	terraform destroy -auto-approve
	@echo "$(GREEN)✓ Recursos destruídos!$(NC)"

status: ## Mostrar status do deployment
	@echo "$(GREEN)Status do Deployment:$(NC)"
	@echo ""
	@echo "Helm Releases:"
	@helm list -n api-app-go || echo "  Nenhuma release encontrada"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n api-app-go
	@echo ""
	@echo "Services:"
	@kubectl get svc -n api-app-go
	@echo ""
	@echo "Ingress:"
	@kubectl get ingress -n api-app-go
	@echo ""

logs: ## Ver logs da aplicação
	@echo "$(YELLOW)Logs do inventory-app:$(NC)"
	kubectl logs -n api-app-go deployment/inventory-app -f

logs-mysql: ## Ver logs do MySQL
	@echo "$(YELLOW)Logs do MySQL:$(NC)"
	kubectl logs -n api-app-go deployment/mysql -f

logs-all: ## Ver logs de todos os pods
	@echo "$(YELLOW)Logs de todos os pods:$(NC)"
	kubectl logs -n api-app-go -l app=inventory-app -f

dash: ## Port-forward para a aplicação
	@echo "$(GREEN)Abrindo acesso à aplicação (http://localhost:10000)$(NC)"
	kubectl port-forward -n api-app-go deployment/inventory-app 10000:10000

dash-mysql: ## Port-forward para MySQL
	@echo "$(GREEN)Abrindo acesso ao MySQL (localhost:3306)$(NC)"
	kubectl port-forward -n api-app-go deployment/mysql 3306:3306

shell-app: ## Executar shell no container da aplikação
	@echo "$(GREEN)Conectando ao shell da aplicação...$(NC)"
	@kubectl exec -it -n api-app-go deployment/inventory-app -- sh

shell-mysql: ## Executar shell no container MySQL
	@echo "$(GREEN)Conectando ao MySQL...$(NC)"
	@kubectl exec -it -n api-app-go deployment/mysql -- mysql -u root -padmin

describe: ## Descrever recurso (especificar RESOURCE)
	@read -p "Nome do recurso: " resource ; \
	kubectl describe -n api-app-go $$resource

get-values: ## Ver valores usados no Helm release
	@echo "$(GREEN)Valores do Helm Release:$(NC)"
	helm get values api-observabilidade -n api-app-go

show: ## Ver estado atual do Terraform
	@terraform show

output: ## Ver outputs do Terraform
	@echo "$(GREEN)Outputs do Terraform:$(NC)"
	@terraform output

state-list: ## Listar recursos no estado Terraform
	@terraform state list

state-show: ## Ver detalhes de um recurso do estado
	@read -p "Recurso (ex: kubernetes_namespace.api_app[0]): " resource ; \
	terraform state show $$resource

clean: ## Limpar arquivos temporários
	@echo "$(YELLOW)Limpando arquivos temporários...$(NC)"
	@rm -f tfplan tfplan.backup
	@echo "$(GREEN)✓ Limpeza concluída!$(NC)"

reinstall: destroy-force apply status ## Reinstalar (destroy + apply)
	@echo "$(GREEN)✓ Reinstalação concluída!$(NC)"

.DEFAULT_GOAL := help
