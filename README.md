# Cloud-Native E-Commerce Platform Infrastructure

## Project Overview

This project demonstrates a production-ready microservices infrastructure for an e-commerce platform, showcasing modern DevOps practices including Kubernetes orchestration, GitOps-based CI/CD, comprehensive monitoring, and security best practices.

## Table of Contents
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
- [Security Measures](#security-measures)
- [Monitoring & Observability](#monitoring--observability)
- [CI/CD Pipeline](#cicd-pipeline)
- [Multi-Environment Strategy](#multi-environment-strategy)
- [Demo Credentials](#demo-credentials)
- [Q&A](#qa)

## Architecture

```
─────────────────────────────────────────────────────────────────┐
                         Internet                                 │
─────────────────────────────────────────────────────────────────┘
                                
                    ───────────▼───────────┐
                        AWS ALB/Ingress    │
                    ───────────┬───────────┘
                                
                    ───────────▼───────────┐
                        NGINX Ingress      │
                         Controller         │
                    ───────────┬───────────┘
                                
        ───────────────────────┼───────────────────────┐
                               │                       │
───────▼────────┐    ┌────────▼────────┐    ┌────────▼────────┐
   Frontend     │    │   API Gateway   │    │   Admin Panel   │
   Service      │    │    Service      │    │    Service      │
────────────────┘    └────────┬────────┘    └─────────────────┘
                               
        ──────────────────────┼──────────────────────┐
                              │                      │
───────▼────────┐    ┌───────▼────────┐    ┌───────▼────────┐
    Product     │    │     Order      │    │     User       │
    Service     │    │    Service     │    │    Service     │
────────┬───────┘    └────────┬───────┘    └───────┬────────┘
                              │                     │
         ─────────────────────┼─────────────────────┘
                               
                    ──────────▼──────────┐
                                          │
                        PostgreSQL /     │
                          MongoDB         │
                        (RDS/Atlas)      │
                    ──────────────────────┘

Observability Stack:
─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 Prometheus  │  │   Grafana   │  │     EFK     │  │   Jaeger    │
─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
```

## Tech Stack

### Core Infrastructure
- **Cloud Provider**: AWS (EKS)
- **Container Orchestration**: Kubernetes (EKS)
- **Container Runtime**: Docker
- **Service Mesh**: Istio (optional)

### Infrastructure as Code
- **Terraform**: AWS infrastructure provisioning
- **Helm**: Kubernetes package management
- **Ansible**: Configuration management

### CI/CD Pipeline
- **GitHub Actions**: Build and test automation
- **ArgoCD**: GitOps continuous deployment
- **SonarQube**: Code quality analysis

### Monitoring & Observability
- **Metrics**: Prometheus + Grafana
- **Logging**: EFK Stack (Elasticsearch, Fluentd, Kibana)
- **Tracing**: Jaeger
- **Alerting**: AlertManager

### Security
- **Secrets Management**: AWS Secrets Manager + Sealed Secrets
- **Policy Enforcement**: OPA (Open Policy Agent)
- **Network Policies**: Calico
- **Image Scanning**: Trivy
- **RBAC**: Kubernetes native RBAC

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured
- kubectl (v1.28+)
- Terraform (v1.5+)
- Helm (v3.12+)
- Docker (v24+)
- Python (v3.9+)
- GitHub Account
- Domain name (optional, for production)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/subrotosharma/ecommerce-project-for-axiler.git
cd ecommerce-project-for-axiler

# Set up environment variables
cp .env.example .env
# Edit .env with your values

# Initialize and deploy infrastructure
make init
make deploy-all

# Access services
make get-urls
```

## Project Structure

```
devops-infrastructure/
���─ terraform/                 # Infrastructure as Code
   ├── environments/         # Environment-specific configs
   │   ├── dev/
   │   ├── staging/
   │   └── prod/
   ├── modules/             # Reusable Terraform modules
   │   ├── eks/
   │   ├── rds/
   │   ├── vpc/
   │   └── iam/
   └── backend.tf
���─ kubernetes/               # Kubernetes manifests
   ├── base/                # Base configurations
   │   ├── namespaces/
   │   ├── services/
   │   └── deployments/
   ├── overlays/           # Environment overlays
   │   ├── dev/
   │   ├── staging/
   │   └── prod/
   └── argocd/             # ArgoCD applications
���─ helm/                    # Helm charts
   ├── charts/
   │   ├── frontend/
   │   ├── api-gateway/
   │   ├── product-service/
   │   ├── order-service/
   │   └── user-service/
   └── values/
���─ ci-cd/                   # CI/CD configurations
   ├── github-actions/
   │   ├── workflows/
   │   └── actions/
   ├── argocd/
   └── jenkins/            # Alternative CI option
���─ monitoring/              # Monitoring stack
   ├── prometheus/
   ├── grafana/
   │   └── dashboards/
   ├── elk/
   └── alerts/
���─ scripts/                 # Automation scripts
   ├── setup/
   ├── deploy/
   └── utils/
���─ docker/                  # Docker configurations
   ├── images/
   └── docker-compose.yml
���─ ansible/                 # Configuration management
   ├── playbooks/
   └── roles/
���─ docs/                    # Documentation
   ├── architecture/
   ├── runbooks/
   └── api/
���─ tests/                   # Test suites
   ├── integration/
   ├── load/
   └── security/
���─ .github/                 # GitHub specific
   └── workflows/
���─ Makefile                 # Build automation
���─ .env.example             # Environment template
── README.md               # This file
```

## Setup Instructions

### Step 1: AWS Infrastructure Setup

```bash
# Navigate to terraform directory
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the infrastructure
terraform apply tfplan

# Save outputs
terraform output -json > ../../../outputs.json
```

### Step 2: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name ecommerce-eks-dev

# Verify connection
kubectl get nodes
```

### Step 3: Install Core Components

```bash
# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f helm/values/nginx-ingress-values.yaml

# Install Cert Manager (for SSL)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Step 4: Deploy Monitoring Stack

```bash
# Deploy Prometheus & Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f helm/values/prometheus-values.yaml

# Deploy EFK Stack
kubectl apply -f monitoring/elk/
```

### Step 5: Setup CI/CD with ArgoCD

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD Server
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Configure ArgoCD applications
kubectl apply -f kubernetes/argocd/
```

### Step 6: Deploy Applications

```bash
# Deploy using kubectl manifests
kubectl apply -f kubernetes/manifests/

# Or deploy via ArgoCD (GitOps)
kubectl apply -f argocd/ecommerce-app.yaml

# Verify deployments
kubectl get pods,svc,ingress
```

### Step 7: Configure GitHub Actions

1. Add the following secrets to your GitHub repository:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `DOCKER_REGISTRY_USERNAME`
   - `DOCKER_REGISTRY_PASSWORD`
   - `KUBECONFIG` (base64 encoded)
   - `SONAR_TOKEN`

2. Push code to trigger workflows

## Security Measures

### 1. Network Security
- **VPC Isolation**: Private subnets for EKS nodes
- **Security Groups**: Restrictive ingress/egress rules
- **Network Policies**: Kubernetes NetworkPolicies implemented

### 2. Access Control
- **RBAC**: Kubernetes RBAC policies
- **IAM Roles**: Service accounts with minimal permissions

### 3. Secrets Management
- **AWS Secrets Manager**: RDS and Redis credentials stored securely
- **Encryption at Rest**: EKS envelope encryption

### 4. Container Security
- **Image Scanning**: Trivy vulnerability scanning in CI/CD pipeline
- **SSL/TLS**: Let's Encrypt certificates for all services

### 5. Infrastructure Security
- **Private Subnets**: EKS worker nodes in private subnets
- **Security Groups**: Controlled access between services

## Monitoring & Observability

### Metrics (Prometheus + Grafana)
- **System Metrics**: CPU, Memory, Disk, Network
- **Application Metrics**: Request rates, latencies, error rates
- **Business Metrics**: Orders, revenue, user activity
- **Custom Dashboards**: Service-specific dashboards

### Logging
- **Container Logs**: Kubernetes native logging
- **Application Logs**: Centralized via kubectl logs

### Alerting
- **Prometheus Alerts**: Basic alerting rules configured
- **Grafana Notifications**: Dashboard-based alerts

## CI/CD Pipeline

### GitHub Actions Workflow

```yaml
Build � Test �� Scan → Package → Deploy to Dev → Integration Tests → Deploy to Staging → Smoke Tests → Manual Approval → Deploy to Prod
```

### Pipeline Stages

1. **Source**: GitHub webhook triggers
2. **Build**: Docker multi-stage builds
3. **Test**: Unit, integration, and E2E tests
4. **Security Scan**: SAST, DAST, dependency scanning
5. **Package**: Push to ECR with semantic versioning
6. **Deploy Dev**: Automatic deployment via ArgoCD
7. **Deploy Staging**: After passing dev tests
8. **Deploy Prod**: Manual approval required

## Multi-Environment Strategy

### Environment Promotion

```
Feature Branch � Dev �� Staging → Production
                 ↓        ↓          ↓
  PR Tests    E2E Tests  Load Tests  Canary
```

### Environment Configurations

| Environment | Replicas | Resources | Auto-scaling | Monitoring |
|------------|----------|-----------|--------------|------------|
| Dev        | 1        | 0.5 CPU, 512Mi | No | Basic |
| Staging    | 2        | 1 CPU, 1Gi | Yes (HPA) | Full |
| Production | 3+       | 2 CPU, 2Gi | Yes (HPA+VPA) | Full + APM |

## Live Demo Credentials

### ArgoCD
- **URL**: https://argocd.subrotosharma.site
- **Username**: admin
- **Password**: Dl23kHFfOL44boNC

### Grafana
- **URL**: https://grafana.subrotosharma.site
- **Username**: admin
- **Password**: prom-operator

### Prometheus
- **URL**: https://prometheus.subrotosharma.site
- **Access**: Direct metrics access

### E-Commerce Application
- **Frontend**: https://axiler.subrotosharma.site
- **Features**: Product catalog, shopping cart, responsive design

## Q&A

### 1. Why did you choose this project?

I chose an e-commerce microservices platform because it represents a real-world, complex system that showcases:
- **Microservices Architecture**: Demonstrates service decomposition, inter-service communication, and distributed system challenges
- **Production Readiness**: Includes all components needed for a production system
- **Scalability Challenges**: E-commerce faces variable load, perfect for demonstrating auto-scaling
- **Security Requirements**: Handles sensitive data (payments, user info), showcasing security best practices
- **Business Value**: Clear business metrics and KPIs to monitor

### 2. How does your infrastructure ensure security and scalability?

**Security:**
- **Defense in Depth**: Multiple security layers from network to application
- **Zero Trust**: No implicit trust, everything requires authentication
- **Shift Left**: Security scanning in CI/CD pipeline
- **Secrets Management**: Centralized, encrypted, and rotated secrets
- **Compliance**: CIS benchmarks, OWASP top 10 protection

**Scalability:**
- **Horizontal Scaling**: HPA for pods, Cluster Autoscaler for nodes
- **Database Scaling**: Read replicas, sharding support
- **Caching Layer**: Redis for session and data caching
- **CDN Integration**: CloudFront for static assets
- **Event-Driven**: Message queues for decoupling

### 3. Describe your CI/CD and monitoring strategy

**CI/CD Strategy:**
- **GitOps**: Git as single source of truth with ArgoCD
- **Progressive Delivery**: Feature flags, canary deployments
- **Automated Testing**: Unit, integration, E2E, performance tests
- **Quality Gates**: Code coverage, security scans must pass
- **Rollback Capability**: Automatic rollback on failures

**Monitoring Strategy:**
- **Four Golden Signals**: Latency, traffic, errors, saturation
- **Business Metrics**: Conversion rates, cart abandonment
- **Proactive Monitoring**: Predictive alerts based on trends
- **Observability**: Metrics, logs, and traces correlation
- **SLO/SLI**: 99.9% availability target with error budgets

### 4. What was your biggest challenge?

The biggest challenge was implementing zero-downtime deployments with database migrations. Solution:
- **Blue-Green Database**: Temporary dual-write during migration
- **Feature Toggles**: Gradual rollout of database changes
- **Backwards Compatibility**: Two-version compatibility requirement
- **Migration Testing**: Automated migration testing in CI/CD
- **Rollback Plan**: Always maintain rollback capability

## Advanced Features

- **GitOps with ArgoCD**: Declarative, versioned infrastructure
- **Auto-scaling**: Horizontal Pod Autoscaler (HPA) implemented
- **SSL/TLS**: Automatic certificate management with Let's Encrypt
- **Multi-Environment**: Dev/Staging/Prod configurations



## Development Documentation

- [Development Notes & Learning Process](docs/DEVELOPMENT_NOTES.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Architecture Decisions](docs/architecture/)

## Project Highlights

This project represents 8 weeks of hands-on learning and implementation:
- **Real-world complexity**: E-commerce platform with multiple microservices
- **Production-ready**: SSL/TLS, monitoring, auto-scaling, disaster recovery
- **Modern DevOps**: GitOps with ArgoCD, Infrastructure as Code, CI/CD automation
- **Security-first**: Network policies, secrets management, vulnerability scanning
- **Multi-environment**: Dev/Staging/Prod with proper promotion pipeline
- **Auto-sync test**: ArgoCD GitOps working perfectly
- **Continuous deployment**: Automatic sync from GitHub to Kubernetes

---

## Live Deployment Status
- **E-Commerce Platform**: https://axiler.subrotosharma.site 
- **Grafana Dashboard**: https://grafana.subrotosharma.site   
- **Prometheus Metrics**: https://prometheus.subrotosharma.site 
- **ArgoCD GitOps**: https://argocd.subrotosharma.site 

