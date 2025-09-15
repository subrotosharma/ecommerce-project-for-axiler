# Makefile for DevOps Infrastructure Project

.PHONY: help init validate plan apply destroy clean test deploy-all

# Variables
ENV ?= dev
AWS_REGION ?= us-east-1
CLUSTER_NAME = $(ENV)-eks
NAMESPACE ?= default
TERRAFORM_DIR = terraform/environments/$(ENV)
DOCKER_REGISTRY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
NC = \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $1, $2}'

# Infrastructure Management
init: ## Initialize Terraform
	@echo "$(GREEN)Initializing Terraform for $(ENV) environment...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init -upgrade
	@echo "$(GREEN)Creating S3 bucket for Terraform state if not exists...$(NC)"
	aws s3api create-bucket --bucket terraform-state-$(ENV) --region $(AWS_REGION) 2>/dev/null || true
	aws s3api put-bucket-versioning --bucket terraform-state-$(ENV) --versioning-configuration Status=Enabled
	aws s3api put-bucket-encryption --bucket terraform-state-$(ENV) \
		--server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating Terraform configuration...$(NC)"
	cd $(TERRAFORM_DIR) && terraform validate
	cd $(TERRAFORM_DIR) && terraform fmt -check

plan: validate ## Plan Terraform changes
	@echo "$(GREEN)Planning Terraform changes for $(ENV)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan

apply: plan ## Apply Terraform changes
	@echo "$(YELLOW)Applying Terraform changes for $(ENV)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform apply tfplan
	@echo "$(GREEN)Infrastructure deployed successfully!$(NC)"
	@make update-kubeconfig

destroy: ## Destroy Terraform infrastructure
	@echo "$(RED)WARNING: This will destroy all infrastructure in $(ENV)!$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$confirm" = "yes" ] || exit 1
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

# Kubernetes Management
update-kubeconfig: ## Update kubeconfig for EKS cluster
	@echo "$(GREEN)Updating kubeconfig for $(CLUSTER_NAME)...$(NC)"
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)
	kubectl config set-context --current --namespace=$(NAMESPACE)

install-ingress: ## Install NGINX Ingress Controller
	@echo "$(GREEN)Installing NGINX Ingress Controller...$(NC)"
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--set controller.service.type=LoadBalancer \
		--set controller.metrics.enabled=true \
		--set controller.podAnnotations."prometheus\.io/scrape"=true \
		--set controller.podAnnotations."prometheus\.io/port"=10254

install-cert-manager: ## Install cert-manager for SSL certificates
	@echo "$(GREEN)Installing cert-manager...$(NC)"
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
	@echo "Waiting for cert-manager to be ready..."
	kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
	kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager

install-metrics-server: ## Install Metrics Server
	@echo "$(GREEN)Installing Metrics Server...$(NC)"
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

install-argocd: ## Install ArgoCD
	@echo "$(GREEN)Installing ArgoCD...$(NC)"
	kubectl create namespace argocd 2>/dev/null || true
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "Waiting for ArgoCD to be ready..."
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	@echo "$(YELLOW)ArgoCD admin password:$(NC)"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""

install-monitoring: ## Install Prometheus and Grafana
	@echo "$(GREEN)Installing Prometheus Stack...$(NC)"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace \
		--values monitoring/prometheus/values.yaml \
		--set grafana.adminPassword=admin123 \
		--wait --timeout 10m

install-elk: ## Install EFK Stack
	@echo "$(GREEN)Installing EFK Stack...$(NC)"
	helm repo add elastic https://helm.elastic.co
	helm repo update
	# Install Elasticsearch
	helm upgrade --install elasticsearch elastic/elasticsearch \
		--namespace logging --create-namespace \
		--set replicas=1 \
		--set minimumMasterNodes=1 \
		--set resources.requests.memory=2Gi \
		--set resources.limits.memory=2Gi
	# Install Kibana
	helm upgrade --install kibana elastic/kibana \
		--namespace logging \
		--set elasticsearchHosts="http://elasticsearch-master:9200"
	# Install Fluentd
	kubectl apply -f monitoring/elk/fluentd-daemonset.yaml

# Docker Operations
docker-login: ## Login to ECR
	@echo "$(GREEN)Logging into ECR...$(NC)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(DOCKER_REGISTRY)

docker-build: docker-login ## Build all Docker images
	@echo "$(GREEN)Building Docker images...$(NC)"
	@for service in frontend api-gateway product-service order-service user-service; do \
		echo "Building $service..."; \
		docker build -t $(DOCKER_REGISTRY)/$(ENV)-$service:latest services/$service/; \
	done

docker-push: docker-build ## Push Docker images to ECR
	@echo "$(GREEN)Pushing Docker images to ECR...$(NC)"
	@for service in frontend api-gateway product-service order-service user-service; do \
		echo "Pushing $service..."; \
		docker push $(DOCKER_REGISTRY)/$(ENV)-$service:latest; \
	done

docker-run-local: ## Run services locally with Docker Compose
	@echo "$(GREEN)Starting local environment with Docker Compose...$(NC)"
	docker-compose -f docker/docker-compose.yml up -d
	@echo "$(GREEN)Services are running!$(NC)"
	@echo "Frontend: http://localhost:3000"
	@echo "API Gateway: http://localhost:8080"
	@echo "Grafana: http://localhost:3001 (admin/admin)"
	@echo "Kibana: http://localhost:5601"
	@echo "Jaeger: http://localhost:16686"

docker-stop-local: ## Stop local Docker Compose services
	@echo "$(YELLOW)Stopping local services...$(NC)"
	docker-compose -f docker/docker-compose.yml down

docker-clean: ## Clean up Docker resources
	@echo "$(YELLOW)Cleaning up Docker resources...$(NC)"
	docker-compose -f docker/docker-compose.yml down -v
	docker system prune -af

# Deployment
deploy-infrastructure: init apply install-ingress install-cert-manager install-metrics-server ## Deploy base infrastructure
	@echo "$(GREEN)Base infrastructure deployed successfully!$(NC)"

deploy-monitoring: install-monitoring install-elk ## Deploy monitoring stack
	@echo "$(GREEN)Monitoring stack deployed successfully!$(NC)"

deploy-argocd: install-argocd ## Deploy ArgoCD
	@echo "$(GREEN)Deploying ArgoCD applications...$(NC)"
	kubectl apply -f kubernetes/argocd/application.yaml
	@echo "$(GREEN)ArgoCD deployed successfully!$(NC)"

deploy-apps: ## Deploy applications using Helm
	@echo "$(GREEN)Deploying applications...$(NC)"
	@for service in frontend api-gateway product-service order-service user-service; do \
		echo "Deploying $service..."; \
		helm upgrade --install $service ./helm/charts/$service \
			--namespace $(NAMESPACE) \
			--set image.repository=$(DOCKER_REGISTRY)/$(ENV)-$service \
			--set image.tag=latest \
			--values ./helm/values/$(ENV)-values.yaml \
			--wait --timeout 5m; \
	done

deploy-all: deploy-infrastructure deploy-monitoring deploy-argocd deploy-apps ## Deploy everything
	@echo "$(GREEN)Full stack deployed successfully!$(NC)"
	@make get-urls

# Testing
test-unit: ## Run unit tests
	@echo "$(GREEN)Running unit tests...$(NC)"
	@for service in frontend api-gateway product-service order-service user-service; do \
		echo "Testing $service..."; \
		cd services/$service && npm test 2>/dev/null || go test ./... 2>/dev/null || python -m pytest 2>/dev/null || true; \
		cd ../..; \
	done

test-integration: ## Run integration tests
	@echo "$(GREEN)Running integration tests...$(NC)"
	python tests/integration/test_api.py

test-smoke: ## Run smoke tests
	@echo "$(GREEN)Running smoke tests...$(NC)"
	python scripts/smoke_tests.py --env $(ENV)

test-load: ## Run load tests
	@echo "$(GREEN)Running load tests...$(NC)"
	locust -f tests/load/locustfile.py --headless -u 100 -r 10 -t 60s --host https://$(ENV).example.com

test-security: ## Run security tests
	@echo "$(GREEN)Running security scans...$(NC)"
	# Scan Kubernetes manifests
	trivy fs --security-checks vuln,config kubernetes/
	# Scan Terraform files
	trivy fs --security-checks vuln,config terraform/
	# Scan Docker images
	@for service in frontend api-gateway product-service order-service user-service; do \
		echo "Scanning $service image..."; \
		trivy image $(DOCKER_REGISTRY)/$(ENV)-$service:latest; \
	done

test-all: test-unit test-integration test-smoke test-security ## Run all tests

# Utilities
get-urls: ## Get all service URLs
	@echo "$(GREEN)Service URLs:$(NC)"
	@echo "$(YELLOW)External URLs:$(NC)"
	@kubectl get ingress -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[0].host,PATH:.spec.rules[0].http.paths[0].path"
	@echo "\n$(YELLOW)LoadBalancer IPs:$(NC)"
	@kubectl get svc -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,EXTERNAL-IP:.status.loadBalancer.ingress[0].hostname" | grep LoadBalancer

get-passwords: ## Get all passwords and secrets
	@echo "$(YELLOW)Passwords and Secrets:$(NC)"
	@echo "ArgoCD Admin Password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d || echo "Not found"
	@echo "\nGrafana Admin Password:"
	@kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d || echo "Not found"
	@echo "\nRDS Password Secret:"
	@aws secretsmanager get-secret-value --secret-id $(ENV)-rds-password --query SecretString --output text | jq -r '.password' || echo "Not found"

logs: ## Tail logs for all pods
	@echo "$(GREEN)Tailing logs for all pods in namespace $(NAMESPACE)...$(NC)"
	stern --all-namespaces --since 1m

port-forward-argocd: ## Port forward ArgoCD UI
	@echo "$(GREEN)Port forwarding ArgoCD UI to http://localhost:8080$(NC)"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

port-forward-grafana: ## Port forward Grafana UI
	@echo "$(GREEN)Port forwarding Grafana to http://localhost:3000$(NC)"
	kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

port-forward-kibana: ## Port forward Kibana UI
	@echo "$(GREEN)Port forwarding Kibana to http://localhost:5601$(NC)"
	kubectl port-forward svc/kibana-kibana -n logging 5601:5601

backup: ## Backup cluster configuration
	@echo "$(GREEN)Backing up cluster configuration...$(NC)"
	mkdir -p backups/$(shell date +%Y%m%d)
	kubectl get all --all-namespaces -o yaml > backups/$(shell date +%Y%m%d)/all-resources.yaml
	kubectl get pv,pvc --all-namespaces -o yaml > backups/$(shell date +%Y%m%d)/storage.yaml
	kubectl get ingress,service --all-namespaces -o yaml > backups/$(shell date +%Y%m%d)/networking.yaml
	@echo "$(GREEN)Backup completed in backups/$(shell date +%Y%m%d)/$(NC)"

clean: docker-clean ## Clean up all resources
	@echo "$(YELLOW)Cleaning up temporary files...$(NC)"
	rm -rf .terraform/
	rm -f terraform/environments/*/tfplan
	rm -f terraform/environments/*/.terraform.lock.hcl
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	@echo "$(GREEN)Cleanup completed!$(NC)"

# Troubleshooting
debug-pods: ## Show pod issues
	@echo "$(YELLOW)Pods not running:$(NC)"
	kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

debug-events: ## Show recent events
	@echo "$(YELLOW)Recent Kubernetes events:$(NC)"
	kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

debug-resources: ## Show resource usage
	@echo "$(YELLOW)Resource usage:$(NC)"
	kubectl top nodes
	kubectl top pods --all-namespaces

validate-deployment: ## Validate the deployment
	@echo "$(GREEN)Validating deployment...$(NC)"
	@scripts/validate-deployment.sh $(ENV)