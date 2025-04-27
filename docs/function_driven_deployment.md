# Function-Driven Deployment Pattern

This guide explains our function-driven deployment pattern, which uses function configuration files to drive infrastructure deployment through Terraform.

## Overview

The function-driven deployment pattern allows developers to define Lambda function configurations in a simple JSON format, which is then used by Terraform to automatically provision the required infrastructure. This approach:

- Simplifies function deployment
- Ensures consistent infrastructure
- Reduces manual configuration
- Enables infrastructure as code for functions

## Function Configuration

Each Lambda function has a `function.json` configuration file that defines its properties. Here's a comprehensive example:

```json
{
  "name": "device_status",
  "description": "Handler for device status updates and monitoring",
  "runtime": "python3.11",
  "handler": "index.lambda_handler",
  "timeout": 30,
  "memory_size": 256,
  "layers": [
    "arn:aws:lambda:us-east-1:123456789012:layer:shared-utils:1"
  ],
  "api": {
    "path": "/devices/{deviceId}/status",
    "methods": ["GET", "POST"],
    "authorizer": "cognito",
    "cors": {
      "allowed_origins": ["https://example.com"],
      "allowed_headers": ["Content-Type", "Authorization"],
      "allowed_methods": ["GET", "POST", "OPTIONS"]
    }
  },
  "environment_variables": {
    "LOG_LEVEL": "INFO",
    "MAX_RETRIES": "3",
    "CACHE_TTL": "300"
  },
  "additional_policies": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/Devices"
    }
  ],
  "vpc_config": {
    "subnet_ids": ["subnet-123456", "subnet-789012"],
    "security_group_ids": ["sg-123456"]
  },
  "dead_letter_config": {
    "target_arn": "arn:aws:sqs:us-east-1:123456789012:dlq-device-status"
  },
  "tracing_config": {
    "mode": "Active"
  },
  "tags": {
    "Environment": "dev",
    "Service": "device-management",
    "Owner": "team-device"
  }
}
```

### Configuration Fields

| Field | Description | Required | Default |
|-------|-------------|----------|---------|
| `name` | Function name (must be unique) | Yes | - |
| `description` | Function description | Yes | - |
| `runtime` | Runtime environment | Yes | - |
| `handler` | Function entry point | Yes | - |
| `timeout` | Execution timeout (seconds) | No | 3 |
| `memory_size` | Memory allocation (MB) | No | 128 |
| `layers` | ARNs of Lambda layers | No | [] |
| `api` | API Gateway configuration | No | null |
| `environment_variables` | Environment variables | No | {} |
| `additional_policies` | Additional IAM policies | No | [] |
| `vpc_config` | VPC configuration | No | null |
| `dead_letter_config` | DLQ configuration | No | null |
| `tracing_config` | X-Ray tracing config | No | {"mode": "PassThrough"} |
| `tags` | Resource tags | No | {} |

### API Configuration

The `api` field supports the following options:

```json
{
  "api": {
    "path": "/devices/{deviceId}/status",
    "methods": ["GET", "POST"],
    "authorizer": "cognito",
    "cors": {
      "allowed_origins": ["https://example.com"],
      "allowed_headers": ["Content-Type", "Authorization"],
      "allowed_methods": ["GET", "POST", "OPTIONS"]
    },
    "request_parameters": {
      "method.request.path.deviceId": true,
      "method.request.querystring.status": false
    },
    "request_validator": {
      "validate_body": true,
      "validate_parameters": true
    }
  }
}
```

### VPC Configuration

For functions requiring VPC access:

```json
{
  "vpc_config": {
    "subnet_ids": ["subnet-123456", "subnet-789012"],
    "security_group_ids": ["sg-123456"],
    "assign_public_ip": false
  }
}
```

### Dead Letter Queue Configuration

For handling failed invocations:

```json
{
  "dead_letter_config": {
    "target_arn": "arn:aws:sqs:us-east-1:123456789012:dlq-device-status",
    "max_receive_count": 3
  }
}
```

## Terraform Integration

The function configuration is used by Terraform to provision the required infrastructure:

```
terraform/
├── environments/          # Environment-specific configurations
│   ├── dev/              # Development environment
│   ├── staging/          # Staging environment
│   └── prod/             # Production environment
├── modules/              # Reusable Terraform modules
│   ├── lambda/           # Lambda function module
│   ├── api_gateway/      # API Gateway module
│   └── iam/              # IAM policies module
└── jenkins_infra/        # Jenkins infrastructure
```

### Lambda Module

The Lambda module reads function configurations and creates the necessary resources:

```hcl
# terraform/modules/lambda/main.tf
module "lambda_function" {
  source = "./modules/lambda"

  for_each = local.function_configs

  name               = each.value.name
  description        = each.value.description
  runtime            = each.value.runtime
  handler            = each.value.handler
  timeout            = each.value.timeout
  memory_size        = each.value.memory_size
  environment        = each.value.environment_variables
  additional_policies = each.value.additional_policies
}
```

### API Gateway Integration

If an API configuration is present, the module creates API Gateway resources:

```hcl
# terraform/modules/api_gateway/main.tf
module "api_gateway" {
  source = "./modules/api_gateway"

  for_each = { for k, v in local.function_configs : k => v if can(v.api) }

  function_name = each.value.name
  path          = each.value.api.path
  methods       = each.value.api.methods
}
```

## Deployment Process

1. **Function Development**:
   ```bash
   # Create function directory
   mkdir -p lambda_functions/device/device_status
   
   # Create function files
   touch lambda_functions/device/device_status/index.py
   touch lambda_functions/device/device_status/function.json
   touch lambda_functions/device/device_status/requirements.txt
   ```

2. **Configure Function**:
   ```json
   {
     "name": "device_status",
     "description": "Handler for device status updates",
     "runtime": "python3.11",
     "handler": "index.lambda_handler",
     "timeout": 30,
     "memory_size": 128,
     "api": {
       "path": "/device_status",
       "methods": ["GET", "POST"]
     }
   }
   ```

3. **Terraform Deployment**:
   ```bash
   # Initialize Terraform
   cd terraform/environments/dev
   terraform init
   
   # Plan infrastructure changes
   terraform plan
   
   # Apply changes
   terraform apply
   ```

## Environment-Specific Configuration

Function configurations can be overridden per environment:

```hcl
# terraform/environments/dev/main.tf
locals {
  function_configs = {
    device_status = merge(
      jsondecode(file("${path.module}/../../lambda_functions/device/device_status/function.json")),
      {
        environment_variables = {
          ENVIRONMENT = "dev"
          LOG_LEVEL   = "DEBUG"
        }
      }
    )
  }
}
```

## Best Practices

1. **Version Control**:
   - Keep function configurations in version control
   - Use environment-specific overrides for sensitive values

2. **Configuration Management**:
   - Use consistent naming conventions
   - Document all configuration options
   - Validate configurations before deployment

3. **Security**:
   - Never store sensitive data in function.json
   - Use environment variables for secrets
   - Apply least privilege IAM policies

4. **Testing**:
   - Validate function configurations
   - Test infrastructure changes in dev/staging
   - Use infrastructure testing tools

## Example Workflow

1. **Create New Function**:
   ```bash
   # Create function structure
   mkdir -p lambda_functions/device/device_status
   touch lambda_functions/device/device_status/function.json
   
   # Add function code
   touch lambda_functions/device/device_status/index.py
   ```

2. **Configure Function**:
   ```json
   {
     "name": "device_status",
     "description": "Device status handler",
     "runtime": "python3.11",
     "handler": "index.lambda_handler",
     "api": {
       "path": "/device_status",
       "methods": ["GET"]
     }
   }
   ```

3. **Deploy Infrastructure**:
   ```bash
   # Plan changes
   terraform plan
   
   # Apply changes
   terraform apply
   ```

4. **Deploy Function Code**:
   ```bash
   # Deploy to dev
   ./scripts/deploy_lambda.sh dev device/device_status
   ``` 