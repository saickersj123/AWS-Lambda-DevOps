#!/bin/bash

set -e

AWS_REGION="us-east-2"  # Change this to match your region
DYNAMO_TABLE="terraform-state-lock"
S3_BUCKET="aws-lambda-tf-state-bucket"

# Check if the AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if S3 bucket exists, create if it doesn't
echo "Checking if S3 bucket exists..."
if ! aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
    echo "Creating S3 bucket for Terraform state: $S3_BUCKET"
    aws s3api create-bucket \
        --bucket $S3_BUCKET \
        --region $AWS_REGION \
        --create-bucket-configuration LocationConstraint=$AWS_REGION

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $S3_BUCKET \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket $S3_BUCKET \
        --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
else
    echo "S3 bucket already exists: $S3_BUCKET"
fi

# Check if DynamoDB table exists, create if it doesn't
echo "Checking if DynamoDB table exists..."
if ! aws dynamodb describe-table --table-name $DYNAMO_TABLE 2>/dev/null; then
    echo "Creating DynamoDB table for Terraform state locking: $DYNAMO_TABLE"
    aws dynamodb create-table \
        --table-name $DYNAMO_TABLE \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $AWS_REGION
    
    # Wait for table to become active
    echo "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name $DYNAMO_TABLE --region $AWS_REGION
else
    echo "DynamoDB table already exists: $DYNAMO_TABLE"
fi

echo "Infrastructure for Terraform state management is ready."
echo "Now running Terraform..."

# Pass all script arguments to terraform
terraform init -upgrade

terraform plan -out=plan.tfplan

terraform apply plan.tfplan

terraform show

terraform output