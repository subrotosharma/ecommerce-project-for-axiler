#!/bin/bash
# Automated backup script for e-commerce platform

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/ecommerce-backup-$DATE"

echo "🔄 Starting backup process..."

# Backup Kubernetes resources
mkdir -p $BACKUP_DIR/kubernetes
kubectl get all --all-namespaces -o yaml > $BACKUP_DIR/kubernetes/all-resources.yaml
kubectl get pv,pvc --all-namespaces -o yaml > $BACKUP_DIR/kubernetes/storage.yaml

# Backup Terraform state
mkdir -p $BACKUP_DIR/terraform
aws s3 cp s3://terraform-state-${AWS_ACCOUNT_ID}-dev/dev/terraform.tfstate $BACKUP_DIR/terraform/

# Backup database (if accessible)
echo "📊 Backup completed: $BACKUP_DIR"
echo "💾 Upload to S3 for long-term storage"

# Upload to S3
aws s3 cp $BACKUP_DIR s3://dev-ecommerce-assets-5b4758b7/backups/ --recursive

echo "✅ Backup process completed successfully!"