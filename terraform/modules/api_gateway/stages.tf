# Additional REST API Gateway Stages
resource "aws_api_gateway_stage" "additional_stages" {
  for_each = local.is_rest_api ? var.additional_stages : {}

  deployment_id = aws_api_gateway_deployment.deployment[0].id
  rest_api_id   = local.rest_api_id
  stage_name    = each.key

  access_log_settings {
    destination_arn = local.log_group_arn
    format          = var.access_log_format
  }

  # Stage variables if provided
  variables = each.value.variables

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-${each.key}-stage"
      Environment = var.environment
      Stage       = each.key
    },
    var.tags
  )
}

# Additional HTTP API Gateway Stages
resource "aws_apigatewayv2_stage" "additional_http_stages" {
  for_each = local.is_http_api ? var.additional_stages : {}
  
  api_id      = local.http_api_id
  name        = each.key
  auto_deploy = true
  
  # Stage variables if provided
  stage_variables = each.value.variables
  
  access_log_settings {
    destination_arn = local.log_group_arn
    format          = var.access_log_format
  }
  
  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-${each.key}-stage"
      Environment = var.environment
      Stage       = each.key
    },
    var.tags
  )
}

# Enable CloudWatch logging for additional REST API stages
resource "aws_api_gateway_method_settings" "additional_stage_settings" {
  for_each = local.is_rest_api ? var.additional_stages : {}

  rest_api_id = local.rest_api_id
  stage_name  = aws_api_gateway_stage.additional_stages[each.key].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = lookup(each.value, "enable_detailed_logging", var.enable_detailed_logging)
    throttling_burst_limit = lookup(each.value, "throttling_burst_limit", -1)
    throttling_rate_limit  = lookup(each.value, "throttling_rate_limit", -1)
    caching_enabled        = lookup(each.value, "caching_enabled", false)
  }
}

# Create locals to determine which stages should have domain mappings
locals {
  # REST API domain mappings
  rest_stages_with_domain_mapping = local.is_rest_api && var.domain_name != null && var.domain_certificate_arn != null ? {
    for k, v in var.additional_stages : k => v if lookup(v, "domain_mapping_enabled", false)
  } : {}
  
  # HTTP API domain mappings
  http_stages_with_domain_mapping = local.is_http_api && var.domain_name != null && var.domain_certificate_arn != null ? {
    for k, v in var.additional_stages : k => v if lookup(v, "domain_mapping_enabled", false)
  } : {}
  
  # Handle domain references for existing APIs
  create_rest_domain = local.is_rest_api && !var.use_existing_api && var.domain_name != null && var.domain_certificate_arn != null
  create_http_domain = local.is_http_api && !var.use_existing_api && var.domain_name != null && var.domain_certificate_arn != null
}

# Domain mappings for additional REST API stages
resource "aws_api_gateway_base_path_mapping" "additional_stage_mapping" {
  for_each = local.rest_stages_with_domain_mapping
  
  api_id      = local.rest_api_id
  domain_name = local.create_rest_domain ? aws_api_gateway_domain_name.domain[0].domain_name : var.domain_name
  stage_name  = each.key
  base_path   = lookup(each.value, "base_path", each.key)
}

# Domain mappings for additional HTTP API stages
resource "aws_apigatewayv2_api_mapping" "additional_http_stage_mapping" {
  for_each = local.http_stages_with_domain_mapping
  
  api_id          = local.http_api_id
  domain_name     = local.create_http_domain ? aws_apigatewayv2_domain_name.http_domain[0].domain_name : var.domain_name
  stage           = aws_apigatewayv2_stage.additional_http_stages[each.key].id
  api_mapping_key = lookup(each.value, "base_path", each.key)
} 