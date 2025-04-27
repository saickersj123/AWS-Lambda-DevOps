#!/bin/bash
# Script to deploy Jenkins infrastructure

set -e

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TERRAFORM_DIR="terraform/jenkins_infrastructure"
TERRAFORM_VARS_FILE="terraform.tfvars"

# Ensure AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}AWS credentials not found in environment variables.${NC}"
    echo -e "${YELLOW}You will be prompted for credentials by Terraform.${NC}"
fi

# Function to check if terraform is installed
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Terraform is not installed.${NC}"
        echo -e "${YELLOW}Please install Terraform first: https://www.terraform.io/downloads.html${NC}"
        exit 1
    fi

    # Check terraform version
    TERRAFORM_VERSION=$(terraform --version | head -n 1 | grep -o 'v[0-9\.]*')
    echo -e "${BLUE}Using Terraform ${TERRAFORM_VERSION}${NC}"
}

# Function to create terraform vars file
create_terraform_vars() {
    if [ -f "${TERRAFORM_DIR}/${TERRAFORM_VARS_FILE}" ]; then
        echo -e "${YELLOW}Terraform variables file already exists at ${TERRAFORM_DIR}/${TERRAFORM_VARS_FILE}${NC}"
        echo -e "${YELLOW}Would you like to overwrite it? (y/n)${NC}"
        read -r OVERWRITE
        if [ "$OVERWRITE" != "y" ]; then
            echo -e "${GREEN}Using existing variables file.${NC}"
            return
        fi
    fi

    echo -e "${BLUE}Creating Terraform variables file...${NC}"
    
    # Prompt for variables
    read -p "AWS Region [us-east-2]: " REGION
    REGION=${REGION:-us-east-2}
    
    read -p "Environment [shared]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-shared}
    
    read -p "EC2 Key Pair Name [jenkins-key]: " KEY_NAME
    KEY_NAME=${KEY_NAME:-jenkins-key}
    
    read -p "Private Key Path [~/.ssh/jenkins-key.pem]: " PRIVATE_KEY_PATH
    PRIVATE_KEY_PATH=${PRIVATE_KEY_PATH:-~/.ssh/jenkins-key.pem}
    
    read -p "EC2 Instance Type [t2.micro]: " INSTANCE_TYPE
    INSTANCE_TYPE=${INSTANCE_TYPE:-t2.micro}
    
    read -p "EBS Volume Size (GB) [30]: " VOLUME_SIZE
    VOLUME_SIZE=${VOLUME_SIZE:-30}
    
    read -p "Jenkins Admin Username [admin]: " JENKINS_ADMIN_USERNAME
    JENKINS_ADMIN_USERNAME=${JENKINS_ADMIN_USERNAME:-admin}
    
    read -p "Jenkins Admin Password [auto-generate]: " JENKINS_ADMIN_PASSWORD
    if [ -z "$JENKINS_ADMIN_PASSWORD" ]; then
        JENKINS_ADMIN_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 16)
        echo "Generated password: $JENKINS_ADMIN_PASSWORD"
    fi
    
    # Write variables to file
    cat > "${TERRAFORM_DIR}/${TERRAFORM_VARS_FILE}" << EOF
region                 = "${REGION}"
environment            = "${ENVIRONMENT}"
key_name               = "${KEY_NAME}"
private_key_path       = "${PRIVATE_KEY_PATH}"
instance_type          = "${INSTANCE_TYPE}"
volume_size            = ${VOLUME_SIZE}
jenkins_admin_username = "${JENKINS_ADMIN_USERNAME}"
jenkins_admin_password = "${JENKINS_ADMIN_PASSWORD}"
EOF

    # Add AWS credentials if available
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        cat >> "${TERRAFORM_DIR}/${TERRAFORM_VARS_FILE}" << EOF
aws_access_key_id     = "${AWS_ACCESS_KEY_ID}"
aws_secret_access_key = "${AWS_SECRET_ACCESS_KEY}"
EOF
    fi

    echo -e "${GREEN}Terraform variables file created at ${TERRAFORM_DIR}/${TERRAFORM_VARS_FILE}${NC}"
}

# Function to initialize terraform
init_terraform() {
    echo -e "${BLUE}Initializing Terraform...${NC}"
    cd "$TERRAFORM_DIR"
    terraform init
    cd - > /dev/null
}

# Function to create terraform plan
plan_terraform() {
    echo -e "${BLUE}Creating Terraform plan...${NC}"
    cd "$TERRAFORM_DIR"
    terraform plan -out=tfplan
    cd - > /dev/null
}

# Function to apply terraform plan
apply_terraform() {
    echo -e "${BLUE}Applying Terraform plan...${NC}"
    cd "$TERRAFORM_DIR"
    terraform apply -auto-approve tfplan
    
    # Display outputs
    echo -e "${GREEN}Jenkins infrastructure deployed successfully!${NC}"
    echo -e "${BLUE}Jenkins URL:${NC}"
    terraform output jenkins_url
    
    cd - > /dev/null
}

# Main function
main() {
    echo -e "${BLUE}Jenkins Infrastructure Deployment Script${NC}"
    echo "====================================="
    
    # Check Terraform
    check_terraform
    
    # Create Terraform vars file
    create_terraform_vars
    
    # Initialize Terraform
    init_terraform
    
    # Create plan
    plan_terraform
    
    # Prompt for confirmation
    echo -e "${YELLOW}Ready to deploy Jenkins infrastructure.${NC}"
    echo -e "${YELLOW}Continue with deployment? (y/n)${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo -e "${RED}Deployment canceled.${NC}"
        exit 0
    fi
    
    # Apply plan
    apply_terraform
}

# Run main function
main 