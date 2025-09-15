#!/bin/bash

# Set variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ENV=dev
export AWS_REGION=us-east-1
BUCKET_NAME="terraform-state-${AWS_ACCOUNT_ID}-${ENV}"

echo "Setting up Terraform backend..."
echo "Bucket name: $BUCKET_NAME"
echo "Region: $AWS_REGION"

# Check if bucket already exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Bucket $BUCKET_NAME already exists"
else
    echo "Creating bucket $BUCKET_NAME..."
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✓ Bucket created successfully"
    else
        echo "✗ Failed to create bucket"
        exit 1
    fi
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

if [ $? -eq 0 ]; then
    echo "✓ Versioning enabled"
else
    echo "✗ Failed to enable versioning"
    exit 1
fi

# Enable encryption
echo "Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

if [ $? -eq 0 ]; then
    echo "✓ Encryption enabled"
else
    echo "✗ Failed to enable encryption"
fi

# Create DynamoDB table
echo "Creating DynamoDB table for state locking..."
aws dynamodb describe-table --table-name terraform-state-lock &>/dev/null || \
aws dynamodb create-table \
    --table-name terraform-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region ${AWS_REGION}

echo "✓ Setup complete!"
echo ""
echo "Bucket: $BUCKET_NAME"
echo "DynamoDB Table: terraform-state-lock"
echo "Region: $AWS_REGION"
