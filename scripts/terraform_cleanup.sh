#!/bin/bash
set -e

# Script to clean up or import existing AWS resources that might be causing conflicts with Terraform
# Usage: ./terraform_cleanup.sh [environment]
# Example: ./terraform_cleanup.sh dev

# Parse arguments
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-2}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Cleaning up Terraform resources for environment: $ENVIRONMENT${NC}"

# Function to handle CloudWatch log groups
handle_cloudwatch_logs() {
    local log_group_name=$1
    local resource_address=$2
    
    echo -e "${YELLOW}Checking if CloudWatch Log Group $log_group_name exists...${NC}"
    
    # For CloudWatch Log Groups, we need to escape the / characters for AWS CLI
    local escaped_log_group_name=$(echo "$log_group_name" | sed 's/\//\\\//g')
    
    # First try with exact name (this is more precise)
    if aws logs describe-log-groups --log-group-name "$log_group_name" 2>/dev/null; then
        echo -e "${GREEN}CloudWatch Log Group $log_group_name exists.${NC}"
        
        # Try to import it
        echo -e "${YELLOW}Attempting to import CloudWatch Log Group into Terraform state...${NC}"
        cd terraform/environments/$ENVIRONMENT
        terraform import $resource_address "$log_group_name" || {
            echo -e "${RED}Failed to import CloudWatch Log Group. Manual resolution needed.${NC}"
            echo -e "${YELLOW}Try adding a lifecycle block to the resource in Terraform code.${NC}"
        }
        cd - >/dev/null
    # Try listing all log groups and grep through the output
    elif aws logs describe-log-groups | grep -q "\"logGroupName\": \"$log_group_name\""; then
        echo -e "${GREEN}CloudWatch Log Group $log_group_name found in the list.${NC}"
        
        # Try to import it
        echo -e "${YELLOW}Attempting to import CloudWatch Log Group into Terraform state...${NC}"
        cd terraform/environments/$ENVIRONMENT
        terraform import $resource_address "$log_group_name" || {
            echo -e "${RED}Failed to import CloudWatch Log Group. Manual resolution needed.${NC}"
            echo -e "${YELLOW}Try adding a lifecycle block to the resource in Terraform code.${NC}"
        }
        cd - >/dev/null
    else
        echo -e "${GREEN}CloudWatch Log Group $log_group_name doesn't exist. No action needed.${NC}"
    fi
}

# Function to handle IAM roles
handle_iam_role() {
    local role_name=$1
    local resource_address=$2
    
    echo -e "${YELLOW}Checking if IAM Role $role_name exists...${NC}"
    
    if aws iam get-role --role-name "$role_name" 2>/dev/null; then
        echo -e "${GREEN}IAM Role $role_name exists.${NC}"
        
        # Try to import it
        echo -e "${YELLOW}Attempting to import IAM Role into Terraform state...${NC}"
        cd terraform/environments/$ENVIRONMENT
        terraform import $resource_address $role_name || {
            echo -e "${RED}Failed to import IAM Role. Manual resolution needed.${NC}"
            echo -e "${YELLOW}Try adding a lifecycle block to the resource in Terraform code.${NC}"
        }
        cd - >/dev/null
    else
        echo -e "${GREEN}IAM Role $role_name doesn't exist. No action needed.${NC}"
    fi
}

# Function to handle S3 buckets
handle_s3_bucket() {
    local bucket_name=$1
    local resource_address=$2
    
    echo -e "${YELLOW}Checking if S3 Bucket $bucket_name exists...${NC}"
    
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        echo -e "${GREEN}S3 Bucket $bucket_name exists.${NC}"
        
        # Try to import it
        echo -e "${YELLOW}Attempting to import S3 Bucket into Terraform state...${NC}"
        cd terraform/environments/$ENVIRONMENT
        terraform import $resource_address $bucket_name || {
            echo -e "${RED}Failed to import S3 Bucket. Manual resolution needed.${NC}"
            echo -e "${YELLOW}Try adding a lifecycle block to the resource in Terraform code.${NC}"
        }
        cd - >/dev/null
    else
        echo -e "${GREEN}S3 Bucket $bucket_name doesn't exist. No action needed.${NC}"
    fi
}

# Function to handle IAM instance profiles
handle_instance_profile() {
    local profile_name=$1
    local resource_address=$2
    
    echo -e "${YELLOW}Checking if IAM Instance Profile $profile_name exists...${NC}"
    
    if aws iam get-instance-profile --instance-profile-name "$profile_name" 2>/dev/null; then
        echo -e "${GREEN}IAM Instance Profile $profile_name exists.${NC}"
        
        # Try to import it
        echo -e "${YELLOW}Attempting to import IAM Instance Profile into Terraform state...${NC}"
        cd terraform/environments/$ENVIRONMENT
        terraform import $resource_address $profile_name || {
            echo -e "${RED}Failed to import IAM Instance Profile. Manual resolution needed.${NC}"
            echo -e "${YELLOW}Try adding a lifecycle block to the resource in Terraform code.${NC}"
        }
        cd - >/dev/null
    else
        echo -e "${GREEN}IAM Instance Profile $profile_name doesn't exist. No action needed.${NC}"
    fi
}

# First, let's handle the CloudWatch Log Group for API Gateway
handle_cloudwatch_logs "/aws/apigateway/${ENVIRONMENT}-PandaCharging" "module.api_gateway.aws_cloudwatch_log_group.api_gateway_logs"

# Special case: Let's check directly for the CloudWatch Log Group using a different approach
echo -e "${YELLOW}Trying alternative approach to check CloudWatch Log Group...${NC}"
LOG_GROUP_NAME="/aws/apigateway/${ENVIRONMENT}-PandaCharging"
if aws logs describe-log-groups | grep -q "\"logGroupName\": \"$LOG_GROUP_NAME\""; then
    echo -e "${GREEN}Found CloudWatch Log Group $LOG_GROUP_NAME. Attempting to import...${NC}"
    cd terraform/environments/$ENVIRONMENT
    terraform import module.api_gateway.aws_cloudwatch_log_group.api_gateway_logs "$LOG_GROUP_NAME" || {
        echo -e "${RED}Failed to import CloudWatch Log Group. Displaying all log groups:${NC}"
        aws logs describe-log-groups | grep "logGroupName"
    }
    cd - >/dev/null
else
    echo -e "${RED}CloudWatch Log Group still not found. Listing all log groups:${NC}"
    aws logs describe-log-groups | grep "logGroupName"
fi

# Handle IAM roles
handle_iam_role "${ENVIRONMENT}-jenkins-role" "module.jenkins.aws_iam_role.jenkins_role"
handle_iam_role "${ENVIRONMENT}-payment-status-role" "module.lambda_functions[\"payment-status\"].aws_iam_role.lambda_role"
handle_iam_role "${ENVIRONMENT}-device-status-role" "module.lambda_functions[\"device-status\"].aws_iam_role.lambda_role"

# Handle S3 bucket
handle_s3_bucket "${ENVIRONMENT}-jenkins-artifacts-pandacharging" "aws_s3_bucket.jenkins_artifacts"

# Handle IAM instance profile
handle_instance_profile "${ENVIRONMENT}-jenkins-profile" "module.jenkins.aws_iam_instance_profile.jenkins_profile"

echo -e "${GREEN}Cleanup script completed. Review any errors above.${NC}"
echo -e "${YELLOW}If issues persist, you may need to manually update your Terraform code with appropriate lifecycle blocks.${NC}" 