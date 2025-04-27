# Jenkins Infrastructure Management

This directory contains Terraform configurations for deploying and managing Jenkins infrastructure, separate from application resources.

## Overview

The Jenkins infrastructure is managed separately from the application infrastructure to avoid circular dependencies and ensure clean separation of concerns. This approach prevents the situation where Jenkins is responsible for deploying its own infrastructure.

## Infrastructure Components

- Dedicated VPC for Jenkins
- Jenkins EC2 instance
- Security groups
- IAM roles and policies
- S3 bucket for Jenkins artifacts

## How to Deploy

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (version 1.0.0 or newer)
3. An EC2 key pair for SSH access to Jenkins

### Deployment Steps

1. Initialize Terraform:

```bash
cd terraform/jenkins_infrastructure
terraform init
```

2. Create a terraform.tfvars file with your specific values (optional):

```hcl
region                 = "us-east-2"
environment            = "shared"
key_name               = "your-key-name"
private_key_path       = "~/.ssh/your-key.pem"
instance_type          = "t2.micro"
volume_size            = 30
jenkins_access_cidr    = ["your-ip/32"]
ssh_access_cidr        = ["your-ip/32"]
jenkins_admin_username = "admin"
jenkins_admin_password = "your-secure-password"
```

3. Create a plan:

```bash
terraform plan -out=tfplan
```

4. Apply the plan:

```bash
terraform apply tfplan
```

5. After deployment, get the Jenkins URL:

```bash
terraform output jenkins_url
```

## Maintenance

### Updating Jenkins Infrastructure

To update the Jenkins infrastructure:

1. Make changes to the Terraform files
2. Create a new plan with `terraform plan -out=tfplan`
3. Apply the changes with `terraform apply tfplan`

### Destroying Jenkins Infrastructure

To completely remove the Jenkins infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete all Jenkins infrastructure. Use with caution.

## Jenkins Configuration

After the infrastructure is deployed, Jenkins needs to be configured with:

1. Required plugins
2. Pipeline jobs
3. AWS credentials for deploying application infrastructure

See the [Jenkins module README](../modules/jenkins/README.md) for more details on configuration. 