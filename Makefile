.PHONY: help build test deploy clean

# Default environment
ENV ?= dev

help: ## Show this help message
	@echo 'Usage: make [target] [ENV=environment]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build all Docker images
	docker compose build

test: ## Run all tests
	@echo "Running API service tests..."
	cd api-service && npm test
	@echo "Running frontend service tests..."
	cd frontend-service && npm test
	@echo "Running worker service tests..."
	cd worker-service && python -m pytest tests/

dev: ## Start development environment
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

local-setup: ## Set up local Kubernetes cluster
	./scripts/local-setup.sh

deploy: ## Deploy to Kubernetes (ENV=dev|staging|production)
	./scripts/deploy.sh $(ENV)

rollback: ## Rollback deployment (ENV=dev|staging|production)
	./scripts/rollback.sh $(ENV)

clean: ## Clean up Docker resources
	docker compose down -v
	docker system prune -f

k8s-clean: ## Clean up Kubernetes resources
	kubectl delete namespace microservices-app-$(ENV) --ignore-not-found=true

logs: ## Show logs for all services
	docker compose logs -f

k8s-logs: ## Show Kubernetes logs
	kubectl logs -l app=api -n microservices-app-$(ENV) --tail=100 -f

status: ## Show status of all services
	@echo "Docker Compose Status:"
	docker compose ps
	@echo ""
	@echo "Kubernetes Status:"
	kubectl get all -n microservices-app-$(ENV)

health: ## Check health of all services
	@echo "Checking API health..."
	curl -f http://localhost:3001/api/health || echo "API not accessible"
	@echo "Checking Frontend..."
	curl -f http://localhost:3000 || echo "Frontend not accessible"