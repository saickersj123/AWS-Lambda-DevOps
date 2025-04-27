# DevOps Setup Guide

This guide provides a comprehensive overview of our AWS Lambda project's DevOps setup, including infrastructure management, CI/CD pipeline, and migration processes.

## Table of Contents
1. [Overview](#overview)
2. [Repository Structure](#repository-structure)
3. [Infrastructure Management](#infrastructure-management)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [Environment Management](#environment-management)
6. [Migration Guide](#migration-guide)
7. [Security and Monitoring](#security-and-monitoring)

## Overview

Our DevOps setup provides a structured approach to developing, testing, and deploying AWS Lambda functions with API Gateway integration. Key components include:

- **Version Control**: Git/GitHub for source code management
- **CI/CD**: Jenkins for continuous integration and deployment
- **Infrastructure as Code**: Terraform for infrastructure management
- **Environment Isolation**: Separate dev, staging, and production environments
- **Shared Utilities**: Lambda Layer for shared code across functions
- **Automated Testing**: Unit and integration tests
- **Infrastructure Testing**: Terraform validation and testing
- **Notification System**: Slack and email notifications

## Repository Structure

```
aws-lambda-project/
├── .github/                 # GitHub workflows
├── terraform/               # Infrastructure as Code
│   ├── environments/        # Environment configurations
│   │   ├── dev/            # Development environment
│   │   ├── staging/        # Staging environment
│   │   └── prod/           # Production environment
│   ├── modules/            # Reusable Terraform modules
│   └── jenkins/            # Jenkins infrastructure
├── jenkins/                 # Jenkins configurations
├── lambda_functions/        # Lambda functions
│   ├── shared_layer/       # Shared layer
│   ├── device/            # Device functions
│   ├── payment/           # Payment functions
│   └── maintenance/       # Maintenance functions
├── tests/                  # Test files
├── scripts/                # Utility scripts
└── docs/                   # Documentation
```

## Infrastructure Management

### Jenkins Infrastructure

Jenkins infrastructure is managed separately from application infrastructure to avoid circular dependencies:

```
                                 ┌────────────────────┐
                                 │                    │
                       deploys   │  Jenkins           │
              ┌─────────────────▶│  Infrastructure    │
              │                  │                    │
              │                  └────────────────────┘
┌─────────────┴─────────┐                 │
│                       │                 │ creates
│  Administrator        │                 │
│  (Manual Deployment)  │                 ▼
│                       │        ┌────────────────────┐
└─────────────┬─────────┘        │                    │
              │                  │  Jenkins Server    │
              │                  │                    │
              │                  └────────────┬───────┘
              │                               │
              │                               │ runs pipelines for
              │         deploys               ▼
              └─────────────────▶ ┌────────────────────┐
                                  │                    │
                                  │  Application       │
                                  │  Infrastructure    │
                                  │                    │
                                  └────────────────────┘
```

### Application Infrastructure

Application infrastructure is deployed through Jenkins using Terraform modules:

1. **Lambda Module**: Deploys Lambda functions with shared layer
2. **API Gateway Module**: Creates API Gateway resources
3. **Lambda Layer Module**: Manages shared utilities
4. **Environment-Specific Configurations**: Each environment has its own Terraform configuration

### State Management

- Jenkins infrastructure: `s3://aws-lambda-tf-state-bucket/jenkins/terraform.tfstate`
- Application infrastructures: 
  - Dev: `s3://aws-lambda-tf-state-bucket/dev/terraform.tfstate`
  - Staging: `s3://aws-lambda-tf-state-bucket/staging/terraform.tfstate`

## CI/CD Pipeline

The Jenkins pipeline includes:

1. **Checkout**: Clone repository
2. **Install Dependencies**: Install required packages
3. **Lint & Format**: Run linting and formatting tools
4. **Unit Tests**: Execute unit tests with coverage
5. **Terraform Init**: Initialize Terraform
6. **Terraform Plan**: Generate deployment plan
7. **Terraform Apply**: Apply infrastructure changes
8. **Integration Tests**: Run integration tests

### Pipeline Features

- Environment selection (dev/staging/prod)
- Coverage reporting (Cobertura)
- Test reporting (JUnit XML)
- Notifications (Slack/email)
- Infrastructure validation

## Environment Management

We maintain three separate environments:

1. **Development (dev)**: Active development and testing
2. **Staging (staging)**: Pre-production testing
3. **Production (prod)**: Live environment

Each environment has its own:
- AWS resources
- API Gateway stages
- Lambda function versions
- Environment variables
- Access controls
- Terraform state

## Migration Guide

### Lambda Function Migration

To migrate Lambda functions to the new structure:

```bash
# Migrate a specific function
./scripts/migrate_lambdas.sh lambda-old device_status

# Migrate all functions
./scripts/migrate_lambdas.sh lambda-old all
```

### Migration Steps

1. **Use Migration Script**:
   - Determines service category
   - Creates directory structure
   - Copies function code
   - Creates documentation
   - Adds shared layer imports

2. **Manual Adjustments**:
   - Update AWS service clients
   - Add error handling decorators
   - Update response formatting
   - Update logging

3. **Update Requirements**:
   - Remove common dependencies (provided by shared layer)
   - Keep function-specific dependencies

4. **Create Documentation**:
   - Function description
   - Features
   - Dependencies
   - Environment variables
   - API Gateway integration
   - Input/Output examples

5. **Create Tests**:
   - Unit tests in `tests/unit/[service]/`
   - Integration tests in `tests/integration/[service]/`

### Service Categories

Functions are categorized into:
- **device**: Device-related functions
- **payment**: Payment-related functions
- **analytics**: Analytics and reporting
- **kiosk**: Kiosk-related functions
- **maintenance**: System maintenance

## Security and Monitoring

### Security Measures

1. **IAM Roles**: Least privilege principle
2. **Environment Isolation**: Prevents production changes from development
3. **Secrets Management**: AWS Secrets Manager
4. **Infrastructure Validation**: Terraform plan review
5. **Manual Approval**: Required for production deployments
6. **Access Controls**: Environment-specific IAM roles
7. **Audit Logging**: CloudTrail logging

### Monitoring

1. **CloudWatch Logs**: Lambda and API Gateway logs
2. **CloudWatch Alarms**: Error rates and performance
3. **X-Ray Tracing**: Request flow tracing
4. **Metrics Dashboard**: Key metrics visualization
5. **Build Notifications**: Slack and email
6. **Infrastructure Monitoring**: Terraform state monitoring

## Getting Started

1. Clone the repository
2. Configure AWS credentials
3. Update Terraform backend configuration
4. Run setup commands:

```bash
# Set up development environment
./scripts/setup_dev_environment.sh

# Initialize Terraform
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# Set up Jenkins credentials
# Create Jenkins pipeline job
``` 