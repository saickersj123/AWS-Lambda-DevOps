provider "aws" {
  region = "us-east-2"
}

# Remote state and locking configuration
terraform {
  backend "s3" {
    bucket         = "aws-lambda-tf-state-bucket"
    key            = "prod/terraform.tfstate"
    region         = "us-east-2"
    use_lockfile   = true
    encrypt        = true
  }
}

# Get AWS account ID for S3 bucket name
data "aws_caller_identity" "current" {}

locals {
  # Filter Lambda functions by environment prefix
  environment_prefix = "${var.environment}_"
  
  # Lambda code base path
  lambda_base_path = "${path.root}/../../../lambda_functions"
  
  # Get all function.json files
  function_jsons = fileset(local.lambda_base_path, "**/function.json")
  
  # Parse function.json files and create a map
  function_configs = {
    for file in local.function_jsons :
    basename(dirname(file)) => {
      name = basename(dirname(file))
      source_dir = "${local.lambda_base_path}/${dirname(file)}"
      config_file = "${local.lambda_base_path}/${file}"
      config = jsondecode(file("${local.lambda_base_path}/${file}"))
      config_hash = filemd5("${local.lambda_base_path}/${file}")
      # Add source code hash for index.py
      source_code_hash = fileexists("${local.lambda_base_path}/${dirname(file)}/index.py") ? filemd5("${local.lambda_base_path}/${dirname(file)}/index.py") : null
    }
  }
  
  # Process functions with their configurations
  processed_functions = {
    for name, data in local.function_configs :
    name => {
      name = name
      source_dir = data.source_dir
      config_hash = data.config_hash
      source_code_hash = data.source_code_hash
      
      api_path = try(
        lookup(lookup(data.config, "api", {}), "path", null), 
        "/${replace(name, "_", "-")}"
      )
      
      # Handle both singular "method" and plural "methods" field
      api_methods = (
        # Check for methods array first
        lookup(lookup(data.config, "api", {}), "methods", null) != null ? 
          lookup(lookup(data.config, "api", {}), "methods", null) :
        # Check if method exists
        lookup(lookup(data.config, "api", {}), "method", null) != null ? 
          # Check if method is already an array
          can(tolist(lookup(lookup(data.config, "api", {}), "method", null))) ?
            lookup(lookup(data.config, "api", {}), "method", null) :
            # If it's a string, convert to single-item array
            [tostring(lookup(lookup(data.config, "api", {}), "method", null))] :
        # Default fallback
        ["GET"]
      )
      
      service_name = try(
        lookup(data.config, "service", null),
        split("_", name)[0],
        "default"
      )
      
      handler = try(
        lookup(data.config, "handler", null),
        "index.handler"
      )
      
      runtime = try(
        lookup(data.config, "runtime", null),
        "python3.11"
      )
      
      timeout = try(
        lookup(data.config, "timeout", null),
        30
      )
      
      memory_size = try(
        lookup(data.config, "memory_size", null),
        128
      )
      
      environment_variables = try(
        lookup(data.config, "environment_variables", {}),
        {}
      )
    }
  }
  
  # Common tags to apply to resources
  common_tags = {
    Environment = var.environment
    Project     = "PandaCharging"
    ManagedBy   = "Terraform"
  }
}

# VPC and Network Resources
module "vpc" {
  source = "../../modules/vpc"
  
  environment = var.environment
  vpc_cidr    = "10.2.0.0/16"
  
  # Use only public subnets since NAT Gateway is disabled
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = []  # No private subnets
  availability_zones   = ["us-east-2a", "us-east-2b"]
  
  # Disable NAT Gateway
  enable_nat_gateway = false
  
  common_tags = local.common_tags
}

# Security Group for Lambda Functions
resource "aws_security_group" "lambda_sg" {
  name   = "${var.environment}-lambda-sg"
  vpc_id = module.vpc.vpc_id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.environment}-lambda-sg"
  })
}

# Lambda Functions Module
module "lambda_functions" {
  source = "../../modules/lambda"
  
  environment      = var.environment
  function_configs = local.processed_functions
  
  # Use public subnets in dev
  vpc_config = {
    subnet_ids         = module.vpc.public_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  
  enable_xray_tracing = true
  log_retention_days  = 30
  
  common_tags = local.common_tags
}

# API Gateway for Lambda Functions
module "api_gateway" {
  source = "../../modules/api_gateway"
  
  environment      = var.environment
  api_name         = "PandaCharging"
  description      = "API Gateway for Lambda functions"
  api_gateway_type = "HTTP"  # Explicitly set to HTTP API Gateway
  
  routes = {
    for name, func in local.processed_functions : name => {
      path          = func.api_path
      methods       = func.api_methods != null ? func.api_methods : ["GET"]
      function_name = name
      authorization = "NONE"
    }
  }
  
  access_log_settings = {
    retention_days = 30
    format        = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\", \"integrationError\":\"$context.integrationErrorMessage\" }"
  }
  
  throttling_settings = {
    burst_limit = 5000
    rate_limit  = 10000
  }
  
  cors_configuration = {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
    expose_headers    = []
    max_age          = 7200
    allow_credentials = false
  }
  
  common_tags = local.common_tags
}

# Output the API Gateway endpoint
output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.api_endpoint
}