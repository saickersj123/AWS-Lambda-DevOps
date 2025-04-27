output "lambda_permissions" {
  description = "Map of created Lambda permissions"
  value = {
    for method in var.http_methods : method => aws_lambda_permission.api_gateway[method].id
  }
}

output "function_name" {
  description = "Name of the Lambda function with permissions"
  value       = var.function_name
} 