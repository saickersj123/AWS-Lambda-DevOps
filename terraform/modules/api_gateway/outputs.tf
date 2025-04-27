output "api_id" {
  description = "ID of the API Gateway"
  value       = local.http_api_id
}

output "api_endpoint" {
  description = "Endpoint URL of the API Gateway"
  value       = local.create_http_api ? aws_apigatewayv2_api.http_api[0].api_endpoint : ""
}

output "api_arn" {
  description = "ARN of the API Gateway"
  value       = local.create_http_api ? aws_apigatewayv2_api.http_api[0].arn : ""
}

output "stage_id" {
  description = "ID of the API Gateway stage"
  value       = local.is_rest_api && length(aws_api_gateway_stage.stage) > 0 ? aws_api_gateway_stage.stage[0].id : (local.is_http_api && length(aws_apigatewayv2_stage.http_stage) > 0 ? aws_apigatewayv2_stage.http_stage[0].id : "")
}

output "stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = local.is_rest_api && length(aws_api_gateway_stage.stage) > 0 ? aws_api_gateway_stage.stage[0].arn : (local.is_http_api && length(aws_apigatewayv2_stage.http_stage) > 0 ? aws_apigatewayv2_stage.http_stage[0].arn : "")
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = local.http_api_execution_arn
}

output "routes" {
  description = "Map of created API Gateway routes"
  value = {
    for route_key, route in aws_apigatewayv2_route.routes : route_key => {
      id        = route.id
      route_key = route.route_key
    }
  }
}

output "integrations" {
  description = "Map of created API Gateway integrations"
  value = {
    for integration_key, integration in aws_apigatewayv2_integration.lambda : integration_key => {
      id  = integration.id
      uri = integration.integration_uri
    }
  }
}

output "api_type" {
  description = "Type of the API Gateway (REST or HTTP)"
  value       = var.api_gateway_type
}

output "invoke_url" {
  description = "Base URL for invoking the API Gateway"
  value       = var.use_existing_api ? "https://${local.http_api_id}.execute-api.${data.aws_region.current.name}.amazonaws.com" : (length(aws_apigatewayv2_stage.http_stage) > 0 ? aws_apigatewayv2_stage.http_stage[0].invoke_url : (local.create_http_api ? aws_apigatewayv2_api.http_api[0].api_endpoint : ""))
}

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = var.environment
}

# Renamed from api_execution_arn to be more explicit
output "api_execution_arn_for_lambda" {
  description = "Execution ARN to use for Lambda permissions (without wildcard paths)"
  value       = local.http_api_execution_arn
}

output "additional_stage_urls" {
  description = "Map of additional stage names to their URLs"
  value       = {
    for stage_name, stage in aws_apigatewayv2_stage.additional_http_stages :
    stage_name => "${stage.invoke_url}"
  }
}

output "domain_name" {
  description = "Custom domain name for the API Gateway"
  value       = var.domain_name != null && var.domain_certificate_arn != null ? aws_apigatewayv2_domain_name.http_domain[0].domain_name : null
}

output "domain_url" {
  description = "URL for the custom domain"
  value       = var.domain_name != null && var.domain_certificate_arn != null ? "https://${aws_apigatewayv2_domain_name.http_domain[0].domain_name}${var.base_path != null ? "/${var.base_path}" : ""}" : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group created for API Gateway logs"
  value       = local.log_group_name
}