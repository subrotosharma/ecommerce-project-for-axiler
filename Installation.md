# Installation Guide

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12
- Docker >= 24.0

## Quick Setup

1. **Clone and configure environment:**
```bash
git clone <repository-url>
cd ecommerce-project-for-axiler
cp .env.example .env
# Edit .env with your AWS credentials and settings
```

2. **Setup Terraform backend:**
```bash
chmod +x complete-script.sh
./complete-script.sh
```

3. **Deploy infrastructure:**
```bash
make init ENV=dev
make apply ENV=dev
```

4. **Configure kubectl:**
```bash
make update-kubeconfig ENV=dev
```

5. **Deploy core components:**
```bash
make install-ingress
make install-cert-manager
make install-metrics-server
```

6. **Deploy monitoring:**
```bash
make install-monitoring
make install-argocd
```

7. **Deploy applications:**
```bash
make deploy-apps ENV=dev
```

8. **Get service URLs:**
```bash
make get-urls
```

## Verification

Check all pods are running:
```bash
kubectl get pods --all-namespaces
```

Access services:
- ArgoCD: `make port-forward-argocd`
- Grafana: `make port-forward-grafana`

## Troubleshooting

- Check pod status: `make debug-pods`
- View events: `make debug-events`
- Check resources: `make debug-resources`