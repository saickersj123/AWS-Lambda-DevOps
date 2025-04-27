output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = module.api_gateway.invoke_url
}

output "api_gateway_stage_urls" {
  description = "URLs for all API Gateway stages"
  value       = module.api_gateway.invoke_url
}

output "lambda_functions" {
  description = "Map of Lambda function details"
  value = {
    for name, _ in local.processed_functions : name => {
      name = module.lambda_functions.function_names[name]
      arn  = module.lambda_functions.function_arns[name]
      role = module.lambda_functions.function_roles[name]
    }
  }
}

output "lambda_log_groups" {
  description = "Map of Lambda function names and their CloudWatch log group ARNs"
  value = module.lambda_functions.log_group_arns
}

output "function_configurations" {
  description = "Processed function configurations"
  value = local.processed_functions
}

output "vpc_details" {
  description = "VPC configuration details"
  value = {
    vpc_id            = module.vpc.vpc_id
    private_subnet_ids = module.vpc.private_subnet_ids
    public_subnet_ids  = module.vpc.public_subnet_ids
  }
}

output "api_gateway_details" {
  description = "API Gateway configuration details"
  value = {
    api_id     = module.api_gateway.api_id
    invoke_url = module.api_gateway.invoke_url
    stage_name = module.api_gateway.stage_name
  }
}