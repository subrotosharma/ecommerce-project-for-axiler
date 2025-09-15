#!/bin/bash
# Deployment Script - scripts/deploy.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENV=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
CLUSTER_NAME="${ENV}-eks"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    for tool in aws kubectl helm terraform docker; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

setup_terraform_backend() {
    log_info "Setting up Terraform backend..."
    
    BUCKET_NAME="terraform-state-${ENV}-${AWS_ACCOUNT_ID}"
    
    # Create S3 bucket for Terraform state
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $AWS_REGION \
        --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || true
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket $BUCKET_NAME \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Create DynamoDB table for state locking
    aws dynamodb create-table \
        --table-name terraform-state-lock \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region $AWS_REGION 2>/dev/null || true
    
    log_info "Terraform backend configured"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd terraform/environments/$ENV
    
    # Initialize Terraform
    terraform init -upgrade
    
    # Plan and apply
    terraform plan -out=tfplan
    terraform apply tfplan -auto-approve
    
    cd ../../..
    
    log_info "Infrastructure deployed successfully"
}

configure_kubectl() {
    log_info "Configuring kubectl..."
    
    aws eks update-kubeconfig \
        --region $AWS_REGION \
        --name $CLUSTER_NAME
    
    # Verify connection
    kubectl get nodes
    
    log_info "kubectl configured successfully"
}

install_cluster_components() {
    log_info "Installing cluster components..."
    
    # Install NGINX Ingress Controller
    log_info "Installing NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx --create-namespace \
        --set controller.service.type=LoadBalancer \
        --set controller.metrics.enabled=true \
        --wait
    
    # Install cert-manager
    log_info "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    
    # Install Metrics Server
    log_info "Installing Metrics Server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    log_info "Cluster components installed"
}

install_monitoring() {
    log_info "Installing monitoring stack..."
    
    # Install Prometheus and Grafana
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring --create-namespace \
        --values monitoring/prometheus/values.yaml \
        --set grafana.adminPassword=admin123 \
        --wait --timeout 10m
    
    log_info "Monitoring stack installed"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    kubectl create namespace argocd 2>/dev/null || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    # Get admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    log_info "ArgoCD admin password: $ARGOCD_PASSWORD"
    
    # Apply ArgoCD applications
    kubectl apply -f kubernetes/argocd/application.yaml
    
    log_info "ArgoCD installed and configured"
}

build_and_push_images() {
    log_info "Building and pushing Docker images..."
    
    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    
    # Build and push each service
    for service in frontend api-gateway product-service order-service user-service; do
        log_info "Building $service..."
        
        # Create ECR repository if not exists
        aws ecr describe-repositories --repository-names "${ENV}-${service}" --region $AWS_REGION 2>/dev/null || \
            aws ecr create-repository --repository-name "${ENV}-${service}" --region $AWS_REGION
        
        # Build and tag image
        docker build -t $service:latest services/$service/
        docker tag $service:latest $ECR_REGISTRY/${ENV}-${service}:latest
        docker tag $service:latest $ECR_REGISTRY/${ENV}-${service}:${GITHUB_SHA:-latest}
        
        # Push to ECR
        docker push $ECR_REGISTRY/${ENV}-${service}:latest
        docker push $ECR_REGISTRY/${ENV}-${service}:${GITHUB_SHA:-latest}
    done
    
    log_info "Docker images built and pushed"
}

deploy_applications() {
    log_info "Deploying applications..."
    
    for service in frontend api-gateway product-service order-service user-service; do
        log_info "Deploying $service..."
        
        helm upgrade --install $service ./helm/charts/$service \
            --namespace default \
            --set image.repository=$ECR_REGISTRY/${ENV}-${service} \
            --set image.tag=${GITHUB_SHA:-latest} \
            --values ./helm/values/${ENV}-values.yaml \
            --wait --timeout 5m
    done
    
    log_info "Applications deployed"
}

run_smoke_tests() {
    log_info "Running smoke tests..."
    
    # Wait for deployments to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/frontend
    kubectl wait --for=condition=available --timeout=300s deployment/api-gateway
    
    # Get ingress URL
    INGRESS_URL=$(kubectl get ingress frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$INGRESS_URL" ]; then
        log_warn "Ingress URL not available yet"
    else
        log_info "Testing application at http://$INGRESS_URL"
        
        # Basic connectivity test
        curl -f http://$INGRESS_URL/health || log_warn "Health check failed"
    fi
    
    log_info "Smoke tests completed"
}

print_summary() {
    echo ""
    echo "========================================="
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo "========================================="
    echo ""
    echo "Environment: $ENV"
    echo "Cluster: $CLUSTER_NAME"
    echo ""
    echo "Access URLs:"
    echo "- ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "- Grafana: kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
    echo "- Application: http://$(kubectl get ingress frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
    echo ""
    echo "Get passwords:"
    echo "- ArgoCD: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    echo "- Grafana: kubectl -n monitoring get secret monitoring-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d"
    echo ""
}

# Main deployment flow
main() {
    log_info "Starting deployment for environment: $ENV"
    
    check_prerequisites
    setup_terraform_backend
    deploy_infrastructure
    configure_kubectl
    install_cluster_components
    install_monitoring
    install_argocd
    build_and_push_images
    deploy_applications
    run_smoke_tests
    print_summary
    
    log_info "Deployment completed successfully!"
}

# Run main function
main