#!/bin/bash
# Multi-environment deployment script

ENV=${1:-dev}
VALID_ENVS=("dev" "staging" "prod")

if [[ ! " ${VALID_ENVS[@]} " =~ " ${ENV} " ]]; then
    echo "❌ Invalid environment: $ENV"
    echo "Valid environments: ${VALID_ENVS[@]}"
    exit 1
fi

echo "🚀 Deploying to $ENV environment..."

# Deploy infrastructure
echo "📦 Deploying infrastructure..."
cd terraform/environments/$ENV
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Deploy applications
echo "🎯 Deploying applications..."
cd ../../../
helm upgrade --install ecommerce-$ENV ./helm/charts/ecommerce \
    --namespace ecommerce-$ENV \
    --create-namespace \
    --values helm/values/$ENV-values.yaml

# Deploy with Kustomize
kubectl apply -k kubernetes/overlays/$ENV

echo "✅ Deployment to $ENV completed!"
echo "🌐 Access URLs:"
case $ENV in
    "dev")
        echo "   - App: https://axiler.subrotosharma.site"
        echo "   - Grafana: https://grafana.subrotosharma.site"
        ;;
    "staging")
        echo "   - App: https://staging.subrotosharma.site"
        ;;
    "prod")
        echo "   - App: https://ecommerce.subrotosharma.site"
        ;;
esac