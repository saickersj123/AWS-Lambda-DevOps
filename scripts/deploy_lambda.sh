#!/bin/bash
# Add explicit bash path to the shebang to ensure bash is used
# Bash supports arrays and other features that sh does not

set -e

# Script to deploy Lambda functions and layers BEFORE Terraform
# Usage: ./scripts/deploy_lambda.sh [environment] [function_name]
# Example: ./scripts/deploy_lambda.sh dev device/device_status
# Example: ./scripts/deploy_lambda.sh dev all

# Parse arguments - use POSIX compatible parameter handling
if [ -n "$1" ]; then
    ENVIRONMENT="$1"
else
    ENVIRONMENT="dev"
fi

if [ -n "$2" ]; then
    FUNCTION_NAME="$2"
else
    FUNCTION_NAME="all"
fi

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display directory structure - helps with debugging
display_directory_structure() {
    local dir="$1"
    local max_depth="$2"
    
    if [ ! -d "$dir" ]; then
        echo -e "${RED}Cannot display structure - directory does not exist: $dir${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Directory structure for $dir (depth $max_depth):${NC}"
    if command -v find &> /dev/null && command -v sort &> /dev/null; then
        find "$dir" -type d -maxdepth "$max_depth" 2>/dev/null | sort | while read -r d; do
            depth=$(echo "$d" | sed -e "s#$dir##" | tr -cd '/' | wc -c)
            indent=$(printf '%*s' "$depth" '')
            echo -e "${indent}$(basename "$d")/"
        done
    else
        echo -e "${YELLOW}Find or sort command not available. Using ls instead.${NC}"
        ls -la "$dir"
    fi
}

# Configuration
echo -e "${BLUE}Configuring deployment for environment: ${ENVIRONMENT}${NC}"
PROJECT_ROOT=$(pwd)
LAMBDA_DIR="${PROJECT_ROOT}/lambda"
SHARED_LAYER_DIR="${LAMBDA_DIR}/shared_layer"
BUILD_DIR="${PROJECT_ROOT}/build"
FUNCTIONS_BUILD_DIR="${BUILD_DIR}/functions"
LAYERS_BUILD_DIR="${BUILD_DIR}/layers"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"

# Show directory structure at the start
echo -e "${BLUE}Lambda directory structure:${NC}"
display_directory_structure "${LAMBDA_DIR}" 3

# Show more detailed debug info at the start
echo -e "${BLUE}Directory information:${NC}"
echo -e "  Current working directory: ${PROJECT_ROOT}"
echo -e "  Lambda directory: ${LAMBDA_DIR}"
echo -e "  Checking if Lambda directory exists: $([ -d "${LAMBDA_DIR}" ] && echo "YES" || echo "NO")"
echo -e "  Script location: $0"
echo -e "  Running as user: $(whoami)"

# Check if the project path contains potentially conflicting names
if echo "${PROJECT_ROOT}" | grep -q "PandaCharging"; then
    echo -e "${YELLOW}WARNING: Jenkins workspace path contains 'PandaCharging', which might cause directory confusion${NC}"
    echo -e "${YELLOW}Will use direct directory listing instead of find to avoid path issues${NC}"
fi

# Add additional checks before trying to find lambda directories
# Ensure we're using the full correct path for SERVICE_DIR
if [ -d "${LAMBDA_DIR}" ]; then
    echo -e "${BLUE}Contents of lambda directory:${NC}"
    ls -la "${LAMBDA_DIR}" || echo -e "${RED}Unable to list contents of ${LAMBDA_DIR}${NC}"
else
    echo -e "${RED}Lambda directory does not exist or is not accessible: ${LAMBDA_DIR}${NC}"
fi

# Verify lambda directory exists
if [ ! -d "${LAMBDA_DIR}" ]; then
    echo -e "${RED}Error: Lambda directory not found at ${LAMBDA_DIR}${NC}"
    echo -e "${YELLOW}Checking directory structure...${NC}"
    ls -la "${PROJECT_ROOT}"
    
    # Try to find lambda directory elsewhere
    echo -e "${YELLOW}Searching for lambda directory...${NC}"
    FOUND_LAMBDA_DIR=$(find "${PROJECT_ROOT}" -name "lambda" -type d | head -n 1)
    
    if [ -n "${FOUND_LAMBDA_DIR}" ]; then
        echo -e "${GREEN}Found lambda directory at: ${FOUND_LAMBDA_DIR}${NC}"
        LAMBDA_DIR="${FOUND_LAMBDA_DIR}"
        SHARED_LAYER_DIR="${LAMBDA_DIR}/shared_layer"
    else
        echo -e "${RED}Could not find lambda directory. Exiting.${NC}"
        exit 1
    fi
fi

# Get AWS account ID first to create unique bucket name
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
DEPLOYMENT_BUCKET="lambda-deployments-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
echo -e "${BLUE}Using deployment bucket: ${DEPLOYMENT_BUCKET}${NC}"

# Check for AWS CLI and set path if needed
if ! command -v aws > /dev/null 2>&1; then
    echo -e "${YELLOW}AWS CLI not found in PATH. Trying to locate it...${NC}"
    
    # Check common installation locations - POSIX-compatible approach
    echo -e "${YELLOW}Checking common AWS CLI installation locations...${NC}"
    
    # Try common paths one by one without using array
    for aws_path in "/usr/local/bin/aws" "/usr/bin/aws" "/root/.local/bin/aws" "/home/$(whoami)/.local/bin/aws" "/opt/aws/bin/aws" "/snap/bin/aws" "/usr/local/aws-cli/v2/current/bin/aws"; do
        if [ -x "$aws_path" ]; then
            echo -e "${GREEN}Found AWS CLI at: $aws_path${NC}"
            # Add to PATH
            export PATH="$(dirname "$aws_path"):$PATH"
            break
        fi
    done
    
    # Check if we found it
    if ! command -v aws > /dev/null 2>&1; then
        echo -e "${RED}Error: AWS CLI not found in PATH or common locations.${NC}"
        echo -e "${YELLOW}Please install AWS CLI with: curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\" && unzip awscliv2.zip && ./aws/install${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Using AWS CLI: $(which aws) - Version: $(aws --version)${NC}"

# Better AWS credentials diagnostic
echo -e "${BLUE}Checking AWS credentials...${NC}"

# Check for credentials in ~/.aws/credentials first (preferred method)
if [ -f ~/.aws/credentials ] && grep -q "aws_access_key_id" ~/.aws/credentials; then
    echo -e "${GREEN}Found AWS credentials in ~/.aws/credentials file${NC}"
    # Using credentials file, no need to set AWS credentials
    USE_CRED_FILE=true
    
    # Extract access key for diagnostic only
    AWS_ACCESS_KEY_ID=$(grep -m1 "aws_access_key_id" ~/.aws/credentials | cut -d= -f2 | tr -d ' ')
else
    USE_CRED_FILE=false
    # Check environment variables as fallback
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        echo -e "${RED}Error: AWS_ACCESS_KEY_ID is not set.${NC}"
        export_required=true
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo -e "${RED}Error: AWS_SECRET_ACCESS_KEY is not set.${NC}"
        export_required=true
    fi
fi

if [ -z "$AWS_DEFAULT_REGION" ]; then
    if [ -f ~/.aws/config ] && grep -q "region" ~/.aws/config; then
        AWS_DEFAULT_REGION=$(grep -m1 "region" ~/.aws/config | cut -d= -f2 | tr -d ' ')
        echo -e "${GREEN}Using region from AWS config file: ${AWS_DEFAULT_REGION}${NC}"
    else
        echo -e "${YELLOW}Warning: AWS_DEFAULT_REGION is not set. Using default: us-east-2${NC}"
        export AWS_DEFAULT_REGION="us-east-2"
    fi
fi

echo -e "${YELLOW}Note: This script is designed to run BEFORE Terraform deployment${NC}"
echo -e "${YELLOW}It will create temporary IAM roles that will be replaced by Terraform${NC}"

# Function to deploy a Lambda function
deploy_function() {
    local SERVICE_NAME="$1"
    local FUNC_NAME="$2"
    
    echo -e "${BLUE}Deploying function: ${SERVICE_NAME}/${FUNC_NAME}${NC}"
    
    local FUNC_DIR="${LAMBDA_DIR}/${SERVICE_NAME}/${FUNC_NAME}"
    local CONFIG_FILE="${FUNC_DIR}/function.json"
    
    # Check if function directory exists
    if [ ! -d "${FUNC_DIR}" ]; then
        echo -e "${RED}Error: Function directory not found at ${FUNC_DIR}${NC}"
        return 1
    fi
    
    # Extract function configuration from function.json
    if [ -f "${CONFIG_FILE}" ]; then
        echo -e "${GREEN}Reading function configuration from ${CONFIG_FILE}${NC}"
        
        if command -v jq &> /dev/null; then
            # Parse function.json using jq
            FUNC_NAME_FROM_JSON=$(jq -r '.name' "${CONFIG_FILE}")
            FUNC_RUNTIME=$(jq -r '.runtime // "python3.11"' "${CONFIG_FILE}")
            FUNC_HANDLER=$(jq -r '.handler // "index.handler"' "${CONFIG_FILE}")
            FUNC_TIMEOUT=$(jq -r '.timeout // 30' "${CONFIG_FILE}")
            FUNC_MEMORY=$(jq -r '.memory_size // 128' "${CONFIG_FILE}")
            
            # Use name from function.json if available
            if [ -n "${FUNC_NAME_FROM_JSON}" ]; then
                LAMBDA_FUNCTION_NAME="${ENVIRONMENT}_${FUNC_NAME_FROM_JSON}"
            else
                LAMBDA_FUNCTION_NAME="${ENVIRONMENT}_${SERVICE_NAME}_${FUNC_NAME}"
            fi
            
            echo -e "${BLUE}Function configuration:${NC}"
            echo -e "  Name: ${LAMBDA_FUNCTION_NAME}"
            echo -e "  Runtime: ${FUNC_RUNTIME}"
            echo -e "  Handler: ${FUNC_HANDLER}"
            echo -e "  Timeout: ${FUNC_TIMEOUT}"
            echo -e "  Memory: ${FUNC_MEMORY}"
        else
            # Fallback to default naming if jq is not available
            LAMBDA_FUNCTION_NAME="${ENVIRONMENT}_${SERVICE_NAME}_${FUNC_NAME}"
            echo -e "${BLUE}Using default name format (jq not available): ${LAMBDA_FUNCTION_NAME}${NC}"
            
            # Default values
            FUNC_RUNTIME="python3.11"
            FUNC_HANDLER="index.handler"
            FUNC_TIMEOUT=30
            FUNC_MEMORY=128
        fi
    else
        # No function.json found, use default naming
        LAMBDA_FUNCTION_NAME="${ENVIRONMENT}_${SERVICE_NAME}_${FUNC_NAME}"
        echo -e "${YELLOW}No function.json found. Using default name format: ${LAMBDA_FUNCTION_NAME}${NC}"
        
        # Default values
        FUNC_RUNTIME="python3.11"
        FUNC_HANDLER="index.handler"
        FUNC_TIMEOUT=30
        FUNC_MEMORY=128
    fi
    
    # Show directory contents for debugging
    echo -e "${BLUE}Contents of function directory:${NC}"
    ls -la "${FUNC_DIR}" || echo -e "${RED}Unable to list contents of ${FUNC_DIR}${NC}"
    
    # Get function name from function.json for role naming
    local FUNC_CONFIG_NAME=$(jq -r '.name // empty' "${CONFIG_FILE}")
    if [ -z "${FUNC_CONFIG_NAME}" ]; then
        FUNC_CONFIG_NAME="${SERVICE_NAME}-${FUNC_NAME}"
    fi
    
    # Always create temporary IAM roles
    echo -e "${YELLOW}Creating temporary IAM role for function (will be replaced by Terraform)...${NC}"
    
    # Generate a role name based on function
    TEMP_ROLE_NAME="${ENVIRONMENT}_${FUNC_CONFIG_NAME}_role"
    
    # Check if role already exists
    if aws iam get-role --role-name "${TEMP_ROLE_NAME}" 2>/dev/null; then
        echo -e "${GREEN}Found existing temporary role: ${TEMP_ROLE_NAME}${NC}"
        ROLE_ARN=$(aws iam get-role --role-name "${TEMP_ROLE_NAME}" --query 'Role.Arn' --output text)
    else
        # Create a basic Lambda execution role
        echo -e "${YELLOW}Creating new role ${TEMP_ROLE_NAME}...${NC}"
        ROLE_ARN=$(aws iam create-role \
            --role-name "${TEMP_ROLE_NAME}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"Service": "lambda.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }]
            }' \
            --tags Key=Environment,Value="${ENVIRONMENT}" Key=ManagedBy,Value="Jenkins" \
            --query 'Role.Arn' --output text)
            
        # Let the role propagate
        echo -e "${YELLOW}Waiting for role to propagate...${NC}"
        sleep 10
            
        # Attach basic policies
        echo -e "${YELLOW}Attaching policies to role...${NC}"
        aws iam attach-role-policy \
            --role-name "${TEMP_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    fi
    
    echo -e "${GREEN}Using IAM role for Lambda: ${ROLE_ARN}${NC}"
    echo -e "${YELLOW}Note: This temporary role will be replaced by Terraform-managed role${NC}"

    # Use existing function zip if already built in the build/functions directory
    if [ -f "${FUNCTIONS_BUILD_DIR}/${SERVICE_NAME}_${FUNC_NAME}.zip" ]; then
        echo -e "${GREEN}Using pre-built function package from Jenkins pipeline${NC}"
        FUNCTION_ZIP="${FUNCTIONS_BUILD_DIR}/${SERVICE_NAME}_${FUNC_NAME}.zip"
    else
        echo -e "${YELLOW}Building function package from source...${NC}"
        
        # Create temp directory for function
        local TEMP_FUNC_DIR="${BUILD_DIR}/temp_${SERVICE_NAME}_${FUNC_NAME}"
        mkdir -p "${TEMP_FUNC_DIR}"
        
        # Copy function contents
        echo -e "${YELLOW}Copying function code from ${FUNC_DIR}...${NC}"
        if ! cp -r "${FUNC_DIR}"/* "${TEMP_FUNC_DIR}/" 2>/dev/null; then
            echo -e "${RED}Error: Failed to copy function code from ${FUNC_DIR}${NC}"
            echo -e "${YELLOW}Checking permissions and content:${NC}"
            ls -la "${FUNC_DIR}"
            return 1
        fi
        
        # Install dependencies if requirements.txt exists
        if [ -f "${TEMP_FUNC_DIR}/requirements.txt" ]; then
            echo -e "${YELLOW}Installing function dependencies...${NC}"
            cd "${TEMP_FUNC_DIR}"
            pip install --quiet -r requirements.txt -t .
            rm -f requirements.txt
        fi
        
        # Create zip package
        mkdir -p "${FUNCTIONS_BUILD_DIR}"
        cd "${TEMP_FUNC_DIR}"
        echo -e "${YELLOW}Creating function zip package...${NC}"
        zip -q -r "${FUNCTIONS_BUILD_DIR}/${SERVICE_NAME}_${FUNC_NAME}.zip" .
        FUNCTION_ZIP="${FUNCTIONS_BUILD_DIR}/${SERVICE_NAME}_${FUNC_NAME}.zip"
        
        # Clean up temp directory
        cd "${PROJECT_ROOT}"
        rm -rf "${TEMP_FUNC_DIR}"
    fi
    
    # Ensure S3 bucket exists
    if ! aws s3api head-bucket --bucket "${DEPLOYMENT_BUCKET}" 2>/dev/null; then
        echo -e "${YELLOW}Creating S3 bucket for Lambda deployments: ${DEPLOYMENT_BUCKET}${NC}"
        aws s3 mb "s3://${DEPLOYMENT_BUCKET}" --region "${AWS_DEFAULT_REGION}"
        aws s3api put-bucket-encryption \
            --bucket "${DEPLOYMENT_BUCKET}" \
            --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    fi
    
    # Upload to S3
    echo -e "${YELLOW}Uploading function to S3...${NC}"
    aws s3 cp "${FUNCTION_ZIP}" "s3://${DEPLOYMENT_BUCKET}/functions/${LAMBDA_FUNCTION_NAME}.zip"
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --query 'Configuration.FunctionName' --output text 2>/dev/null; then
        echo -e "${GREEN}Updating existing function: ${LAMBDA_FUNCTION_NAME}${NC}"
        
        # Get and show current tags for debugging
        LAMBDA_ARN=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --query 'Configuration.FunctionArn' --output text)
        echo -e "${BLUE}Current Lambda ARN: ${LAMBDA_ARN}${NC}"
        
        # Get current Lambda configuration if any
        CURRENT_CONFIG=$(aws lambda get-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --query 'Environment.Variables' --output json 2>/dev/null || echo "{}")
        echo -e "${BLUE}Current Lambda configuration:${NC}"
        echo "${CURRENT_CONFIG}" | jq '.' || echo "${CURRENT_CONFIG}"
        
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --s3-bucket "${DEPLOYMENT_BUCKET}" \
            --s3-key "functions/${LAMBDA_FUNCTION_NAME}.zip" \
            --publish
        
        # Wait for the function to be active after code update before trying to update configuration
        echo -e "${YELLOW}Waiting for function to be active after code update...${NC}"
        WAIT_TIME=0
        MAX_WAIT=30
        FUNCTION_READY=false
        
        while [ ${WAIT_TIME} -lt ${MAX_WAIT} ] && [ "${FUNCTION_READY}" = "false" ]; do
            # Check function state
            FUNCTION_STATE=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" \
                --query 'Configuration.State' --output text 2>/dev/null || echo "Failed")
                
            if [ "${FUNCTION_STATE}" = "Active" ]; then
                FUNCTION_READY=true
                echo -e "${GREEN}Function is now active and ready for configuration update.${NC}"
            else
                echo -e "${YELLOW}Function is in ${FUNCTION_STATE} state after code update. Waiting...${NC}"
                sleep 3
                WAIT_TIME=$((WAIT_TIME + 3))
            fi
        done
        
        if [ "${FUNCTION_READY}" = "false" ]; then
            echo -e "${YELLOW}Function is taking longer than expected to become active.${NC}"
            echo -e "${YELLOW}Adding extra wait time before configuration update...${NC}"
            sleep 10
        fi
        
        # Update function configuration with values from function.json
        echo -e "${YELLOW}Updating function configuration...${NC}"
        
        # Add retry logic with exponential backoff for configuration update
        CONFIG_UPDATE_RETRY_COUNT=0
        CONFIG_UPDATE_MAX_RETRIES=5
        CONFIG_UPDATE_SUCCESS=false
        BACKOFF_TIME=5
        
        while [ ${CONFIG_UPDATE_RETRY_COUNT} -lt ${CONFIG_UPDATE_MAX_RETRIES} ] && [ "${CONFIG_UPDATE_SUCCESS}" = "false" ]; do
            # Try to update function configuration
            if aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
                --runtime "${FUNC_RUNTIME}" \
                --handler "${FUNC_HANDLER}" \
                --timeout "${FUNC_TIMEOUT}" \
                --memory-size "${FUNC_MEMORY}" \
                --role "${ROLE_ARN}" 2>/dev/null; then
                CONFIG_UPDATE_SUCCESS=true
                echo -e "${GREEN}Successfully updated function configuration.${NC}"
            else
                CONFIG_UPDATE_RETRY_COUNT=$((CONFIG_UPDATE_RETRY_COUNT + 1))
                echo -e "${YELLOW}Failed to update function configuration. Retry ${CONFIG_UPDATE_RETRY_COUNT}/${CONFIG_UPDATE_MAX_RETRIES}...${NC}"
                echo -e "${YELLOW}Waiting ${BACKOFF_TIME} seconds before next attempt...${NC}"
                sleep ${BACKOFF_TIME}
                # Exponential backoff with jitter
                BACKOFF_TIME=$((BACKOFF_TIME * 2))
                # Add some random jitter (1-3 seconds)
                JITTER=$((RANDOM % 3 + 1))
                BACKOFF_TIME=$((BACKOFF_TIME + JITTER))
                
                # Add additional check to verify function state explicitly
                echo -e "${YELLOW}Checking function state again...${NC}"
                FUNCTION_STATE=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" \
                    --query 'Configuration.State' --output text 2>/dev/null || echo "Failed")
                echo -e "${YELLOW}Current function state: ${FUNCTION_STATE}${NC}"
                
                if [ "${FUNCTION_STATE}" != "Active" ]; then
                    echo -e "${YELLOW}Function is not yet active. Waiting for it to become active...${NC}"
                    # Wait for function to become active
                    ACTIVE_WAIT_TIME=0
                    ACTIVE_MAX_WAIT=30
                    while [ ${ACTIVE_WAIT_TIME} -lt ${ACTIVE_MAX_WAIT} ] && [ "${FUNCTION_STATE}" != "Active" ]; do
                        sleep 3
                        ACTIVE_WAIT_TIME=$((ACTIVE_WAIT_TIME + 3))
                        FUNCTION_STATE=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" \
                            --query 'Configuration.State' --output text 2>/dev/null || echo "Failed")
                        echo -e "${YELLOW}Function state: ${FUNCTION_STATE}${NC}"
                    done
                fi
                
                # Even if it reports active, add a safety delay
                echo -e "${YELLOW}Adding safety delay before next attempt...${NC}"
                sleep 5
            fi
        done
        
        if [ "${CONFIG_UPDATE_SUCCESS}" = "false" ]; then
            echo -e "${RED}Could not update function configuration after ${CONFIG_UPDATE_MAX_RETRIES} attempts.${NC}"
            echo -e "${YELLOW}Continuing with deployment but function configuration may not be updated.${NC}"
        fi
    else
        echo -e "${YELLOW}Creating new function: ${LAMBDA_FUNCTION_NAME}${NC}"
        
        # Create function with values from function.json
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime "${FUNC_RUNTIME}" \
            --handler "${FUNC_HANDLER}" \
            --timeout "${FUNC_TIMEOUT}" \
            --memory-size "${FUNC_MEMORY}" \
            --role "${ROLE_ARN}" \
            --code "S3Bucket=${DEPLOYMENT_BUCKET},S3Key=functions/${LAMBDA_FUNCTION_NAME}.zip" \
            --tags "Environment=${ENVIRONMENT},Service=${SERVICE_NAME},Function=${FUNC_NAME}" \
            --publish
            
        # Wait for the function to be fully created before continuing
        echo -e "${YELLOW}Waiting for function to be fully deployed...${NC}"
        # Wait for up to 30 seconds for the function to be ready
        WAIT_TIME=0
        MAX_WAIT=30
        FUNCTION_READY=false
        
        while [ ${WAIT_TIME} -lt ${MAX_WAIT} ] && [ "${FUNCTION_READY}" = "false" ]; do
            # Check function state
            FUNCTION_STATE=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" \
                --query 'Configuration.State' --output text 2>/dev/null || echo "Failed")
                
            if [ "${FUNCTION_STATE}" = "Active" ]; then
                FUNCTION_READY=true
                echo -e "${GREEN}Function is now active and ready.${NC}"
            else
                echo -e "${YELLOW}Function is in ${FUNCTION_STATE} state. Waiting...${NC}"
                sleep 3
                WAIT_TIME=$((WAIT_TIME + 3))
            fi
        done
        
        if [ "${FUNCTION_READY}" = "false" ]; then
            echo -e "${YELLOW}Function is taking longer than expected to become active.${NC}"
            echo -e "${YELLOW}Will proceed anyway, but subsequent operations may fail.${NC}"
            # Add an additional safety delay
            sleep 5
        fi
    fi
    
    # Configure concurrency if specified in function.json
    if command -v jq &> /dev/null && [ -f "${CONFIG_FILE}" ]; then
        local CONCURRENCY=$(jq -r '.reserved_concurrency // empty' "${CONFIG_FILE}")
        if [ -n "${CONCURRENCY}" ]; then
            echo -e "${YELLOW}Setting reserved concurrency to ${CONCURRENCY}${NC}"
            # Add retry logic for setting concurrency
            RETRY_COUNT=0
            MAX_RETRIES=3
            SUCCESS=false
            
            while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ] && [ "${SUCCESS}" = "false" ]; do
                if aws lambda put-function-concurrency \
                    --function-name "${LAMBDA_FUNCTION_NAME}" \
                    --reserved-concurrent-executions "${CONCURRENCY}" 2>/dev/null; then
                    SUCCESS=true
                    echo -e "${GREEN}Successfully set concurrency.${NC}"
                else
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    echo -e "${YELLOW}Failed to set concurrency. Retry ${RETRY_COUNT}/${MAX_RETRIES}...${NC}"
                    sleep 5
                fi
            done
            
            if [ "${SUCCESS}" = "false" ]; then
                echo -e "${YELLOW}Could not set concurrency after ${MAX_RETRIES} attempts. Continuing...${NC}"
            fi
        fi
    fi
    
    echo -e "${GREEN}Successfully deployed function: ${LAMBDA_FUNCTION_NAME}${NC}"
    return 0
}

# Main deployment process
echo -e "${BLUE}Starting deployment process...${NC}"

# Create build directories if they don't exist
mkdir -p "${BUILD_DIR}"
mkdir -p "${FUNCTIONS_BUILD_DIR}"
mkdir -p "${LAYERS_BUILD_DIR}"

# Deploy functions
if [ "${FUNCTION_NAME}" == "all" ]; then
    echo -e "${BLUE}Deploying all Lambda functions...${NC}"
    
    # Find functions using function.json files
    echo -e "${YELLOW}Discovering Lambda functions using function.json files...${NC}"
    
    # Create a temp file to track functions
    TEMP_FUNCTIONS_FILE=$(mktemp /tmp/lambda-functions.XXXXXX)
    
    # Find all function.json files recursively
    find "${LAMBDA_DIR}" -name "function.json" -type f -not -path "*/shared_layer/*" > "${TEMP_FUNCTIONS_FILE}"
    
    # Check if we found any functions
    if [ ! -s "${TEMP_FUNCTIONS_FILE}" ]; then
        echo -e "${RED}No function.json files found in ${LAMBDA_DIR}.${NC}"
        rm "${TEMP_FUNCTIONS_FILE}"
        exit 1
    fi
    
    # Process each function.json file
    while read -r CONFIG_FILE; do
        FUNC_DIR=$(dirname "${CONFIG_FILE}")
        REL_PATH="${FUNC_DIR#${LAMBDA_DIR}/}"
        SERVICE_NAME=$(echo "${REL_PATH}" | cut -d'/' -f1)
        FUNC_NAME=$(echo "${REL_PATH}" | cut -d'/' -f2)
        
        echo -e "${BLUE}Found function with config: ${SERVICE_NAME}/${FUNC_NAME}${NC}"
        deploy_function "${SERVICE_NAME}" "${FUNC_NAME}"
    done < "${TEMP_FUNCTIONS_FILE}"
    
    # Clean up temp file
    rm "${TEMP_FUNCTIONS_FILE}"
else
    # Parse function name to get service and function parts
    if [[ "${FUNCTION_NAME}" == *"/"* ]]; then
        # Format is service/function
        SERVICE_NAME=$(echo "${FUNCTION_NAME}" | cut -d'/' -f1)
        FUNC_NAME=$(echo "${FUNCTION_NAME}" | cut -d'/' -f2)
    else
        # Try to find the service directory containing this function
        SERVICE_NAME=""
        FUNC_NAME="${FUNCTION_NAME}"
        
        echo -e "${YELLOW}Searching for service containing function ${FUNC_NAME}...${NC}"
        if [ -d "${LAMBDA_DIR}" ]; then
            for SERVICE_DIR in $(find "${LAMBDA_DIR}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | grep -v "shared_layer"); do
                SERVICE_NAME=$(basename "${SERVICE_DIR}")
                # Check directly if function directory exists
                if [ -d "${SERVICE_DIR}/${FUNC_NAME}" ]; then
                    echo -e "${GREEN}Found function ${FUNC_NAME} in service ${SERVICE_NAME}.${NC}"
                    break
                fi
            done
        else
            echo -e "${RED}Error: Lambda directory not found at ${LAMBDA_DIR}.${NC}"
        fi
        
        if [ -z "${SERVICE_NAME}" ]; then
            echo -e "${RED}Error: Could not determine service name for function ${FUNC_NAME}${NC}"
            echo -e "${YELLOW}Please specify as service/function (e.g. device/device_status)${NC}"
            exit 1
        fi
    fi
    
    echo -e "${BLUE}Deploying single function: ${SERVICE_NAME}/${FUNC_NAME}${NC}"
    
    # Verify function directory exists with better error handling
    FUNC_PATH="${LAMBDA_DIR}/${SERVICE_NAME}/${FUNC_NAME}"
    if [ ! -d "${FUNC_PATH}" ]; then
        echo -e "${RED}Error: Function directory not found at ${FUNC_PATH}${NC}"
        echo -e "${YELLOW}Checking service directory...${NC}"
        
        SERVICE_PATH="${LAMBDA_DIR}/${SERVICE_NAME}"
        if [ -d "${SERVICE_PATH}" ]; then
            echo -e "${YELLOW}Available functions in ${SERVICE_NAME}:${NC}"
            ls -la "${SERVICE_PATH}" || echo -e "${RED}Unable to list contents of ${SERVICE_PATH}${NC}"
        else
            echo -e "${RED}Service directory not found: ${SERVICE_PATH}${NC}"
            echo -e "${YELLOW}Available services in lambda directory:${NC}"
            ls -la "${LAMBDA_DIR}" || echo -e "${RED}Unable to list contents of ${LAMBDA_DIR}${NC}"
        fi
        
        exit 1
    fi
    
    deploy_function "${SERVICE_NAME}" "${FUNC_NAME}"
fi

echo -e "${GREEN}Deployment completed successfully!${NC}" 
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Run Terraform to create/update API Gateway integrations and Lambda permissions:"
echo -e "   cd ${TERRAFORM_DIR} && terraform apply"
echo -e "2. Run integration tests to verify the deployment" 