locals {
  is_rest_api = var.api_gateway_type == "REST"
  is_http_api = var.api_gateway_type == "HTTP"
  
  # Determine if we should create a new API or use an existing one
  create_rest_api = local.is_rest_api && !var.use_existing_api
  create_http_api = local.is_http_api && !var.use_existing_api
  
  # Use existing API ID if specified, otherwise use the created API ID
  rest_api_id = var.use_existing_api ? var.existing_api_id : (local.create_rest_api ? aws_api_gateway_rest_api.api[0].id : "")
  http_api_id = var.use_existing_api ? var.existing_api_id : (local.create_http_api ? aws_apigatewayv2_api.http_api[0].id : "")
  
  # Add safe references for execution ARNs
  rest_api_execution_arn = var.use_existing_api ? (
    local.is_rest_api ? "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.existing_api_id}" : ""
  ) : (local.create_rest_api ? aws_api_gateway_rest_api.api[0].execution_arn : "")
  
  http_api_execution_arn = var.use_existing_api ? (
    local.is_http_api ? "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.existing_api_id}" : ""
  ) : (local.create_http_api ? aws_apigatewayv2_api.http_api[0].execution_arn : "")

  # Flatten the endpoints map to create individual routes for each method
  http_routes = flatten([
    for name, endpoint in var.endpoints : [
      for method in lookup(endpoint, "methods", ["GET"]) : {
        key = "${name}-${method}"
        path = endpoint.path
        method = method
        function_name = endpoint.function_name
      }
    ]
  ])
  
  # Convert the flattened list to a map with keys
  http_routes_map = {
    for route in local.http_routes : route.key => route
  }
}

# Get current AWS region and account ID for ARN construction
# data "aws_region" "current" {}
# data "aws_caller_identity" "current" {}

# REST API Gateway
resource "aws_api_gateway_rest_api" "api" {
  count = var.api_gateway_type == "REST" ? 1 : 0

  name        = "${var.environment}_${var.api_name}"
  description = var.description

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}_${var.api_name}"
    Environment = var.environment
  })
}

# HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  count       = local.create_http_api ? 1 : 0
  name        = "${var.environment}-${var.api_name}"
  description = var.description
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = var.cors_configuration.allow_origins
    allow_methods     = var.cors_configuration.allow_methods
    allow_headers     = var.cors_configuration.allow_headers
    expose_headers    = var.cors_configuration.expose_headers
    max_age           = var.cors_configuration.max_age
    allow_credentials = var.cors_configuration.allow_credentials
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}"
      Environment = var.environment
    },
    var.tags
  )
}

# API Gateway Resource (REST API only) - Path part represents the resource path
resource "aws_api_gateway_resource" "resource" {
  count       = length(var.resource_paths) > 0 && local.is_rest_api ? length(var.resource_paths) : 0
  rest_api_id = local.rest_api_id
  parent_id   = var.resource_parent_ids != null ? var.resource_parent_ids[count.index] : aws_api_gateway_rest_api.api[0].root_resource_id
  path_part   = var.resource_paths[count.index]
  
  # Handle case where resource already exists
  lifecycle {
    ignore_changes = [
      parent_id
    ]
  }
}

# API Gateway Method (REST API only)
resource "aws_api_gateway_method" "method" {
  count         = length(var.http_methods) > 0 && local.is_rest_api ? length(var.http_methods) : 0
  rest_api_id   = local.rest_api_id
  resource_id   = var.method_resource_ids != null ? var.method_resource_ids[count.index] : aws_api_gateway_resource.resource[count.index].id
  http_method   = var.http_methods[count.index]
  authorization = var.authorization_type
  authorizer_id = var.authorizer_id
  
  # Handle case where method already exists
  lifecycle {
    ignore_changes = [
      resource_id
    ]
  }
}

# API Gateway Integration (REST API only)
resource "aws_api_gateway_integration" "integration" {
  count                   = length(var.http_methods) > 0 && local.is_rest_api ? length(var.http_methods) : 0
  rest_api_id             = local.rest_api_id
  resource_id             = var.method_resource_ids != null ? var.method_resource_ids[count.index] : aws_api_gateway_resource.resource[count.index].id
  http_method             = aws_api_gateway_method.method[count.index].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arns[count.index]
  
  # Handle case where integration already exists
  lifecycle {
    ignore_changes = [
      resource_id,
      uri
    ]
  }
}

# HTTP API Routes and Integrations
resource "aws_apigatewayv2_route" "http_route" {
  for_each = local.is_http_api ? local.http_routes_map : {}
  
  api_id    = local.http_api_id
  route_key = "${each.value.method} ${each.value.path}"
  target    = "integrations/${aws_apigatewayv2_integration.http_integration[each.key].id}"
}

resource "aws_apigatewayv2_integration" "http_integration" {
  for_each = local.is_http_api ? local.http_routes_map : {}
  
  api_id             = local.http_api_id
  integration_type   = "AWS_PROXY"
  integration_uri    = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.environment == "prod" ? each.value.function_name : "${var.environment}_${each.value.function_name}"}"
  integration_method = "POST"
  payload_format_version = "2.0"
  description        = "Integration for ${each.value.function_name} function"
}

# Lambda permissions for HTTP API
resource "aws_lambda_permission" "http_api_permission" {
  for_each = local.is_http_api ? {
    for idx, route in flatten([
      for route_key, route in var.routes : [
        for method in route.methods : {
          key           = "${route_key}_${method}"
          path          = route.path
          method        = method
          function_name = route.function_name
        }
      ]
    ]) : route.key => route
  } : {}
  
  statement_id  = "AllowExecutionFromAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.environment == "prod" ? each.value.function_name : "${var.environment}_${each.value.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.http_api_execution_arn}/*/${each.value.method}${each.value.path}"
}

# API Gateway Deployment (REST API only)
resource "aws_api_gateway_deployment" "deployment" {
  count       = local.is_rest_api ? 1 : 0
  rest_api_id = local.rest_api_id
  
  depends_on = [
    aws_api_gateway_integration.integration
  ]
  
  # Ensure a new deployment happens when routes/methods change
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage (REST API only)
resource "aws_api_gateway_stage" "stage" {
  count = local.is_rest_api ? 1 : 0
  deployment_id = aws_api_gateway_deployment.deployment[0].id
  rest_api_id   = local.rest_api_id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = local.log_group_arn
    format          = var.access_log_format
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-stage"
      Environment = var.environment
    },
    var.tags
  )
  
  # Handle case where stage already exists
  lifecycle {
    ignore_changes = [
      deployment_id
    ]
  }
  
  # Ensure the stage is created only after the deployment is created
  depends_on = [
    aws_api_gateway_deployment.deployment
  ]
}

# HTTP API Stage (HTTP API only)
resource "aws_apigatewayv2_stage" "http_stage" {
  count       = local.is_http_api && !var.use_existing_api ? 1 : 0
  api_id      = local.http_api_id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = local.log_group_arn
    format          = jsonencode(var.http_access_log_format)
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-http-stage"
      Environment = var.environment
    },
    var.tags
  )
  
  # Handle case where stage already exists
  lifecycle {
    ignore_changes = [deployment_id]
  }
}

# HTTP API Stage for Existing API (HTTP API only)
resource "aws_apigatewayv2_stage" "existing_http_stage" {
  count       = local.is_http_api && var.use_existing_api ? 1 : 0
  api_id      = local.http_api_id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = local.log_group_arn
    format          = jsonencode(var.http_access_log_format)
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-http-stage"
      Environment = var.environment
    },
    var.tags
  )
  
  # If stage already exists, don't try to recreate it
  lifecycle {
    ignore_changes = [deployment_id]
    create_before_destroy = true
  }
}

# Dummy deployment for existing REST API
resource "aws_api_gateway_deployment" "existing_deployment" {
  count = local.is_rest_api && var.use_existing_api ? 1 : 0
  rest_api_id = local.rest_api_id
  
  # Ensure we have a stable deployment, even without methods
  # This uses a timestamp to force a new deployment when needed
  triggers = {
    redeployment = sha256(jsonencode({
      timestamp = timestamp()
    }))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# REST API Stage for Existing API (REST API only)
resource "aws_api_gateway_stage" "existing_rest_stage" {
  count = local.is_rest_api && var.use_existing_api ? 1 : 0
  rest_api_id = local.rest_api_id
  deployment_id = aws_api_gateway_deployment.existing_deployment[0].id
  stage_name  = var.environment
  description = "Stage for ${var.environment} environment"
  
  # Set up access logging
  access_log_settings {
    destination_arn = local.log_group_arn
    format          = var.access_log_format
  }
  
  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-stage"
      Environment = var.environment
    },
    var.tags
  )
  
  # If stage already exists, handle gracefully
  lifecycle {
    ignore_changes = [deployment_id]
    create_before_destroy = true
  }
}

# Create the CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.create_log_group ? 1 : 0
  name              = "/aws/apigateway/${var.environment}-${var.api_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-logs"
      Environment = var.environment
    },
    var.tags
  )
}

# Local to reference the log group
locals {
  log_group_arn = var.create_log_group ? aws_cloudwatch_log_group.api_gateway_logs[0].arn : ""
  log_group_name = var.create_log_group ? aws_cloudwatch_log_group.api_gateway_logs[0].name : ""
}

# Enable CloudWatch logging for REST API Gateway
resource "aws_api_gateway_method_settings" "settings" {
  count = local.is_rest_api ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  stage_name  = aws_api_gateway_stage.stage[0].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = var.enable_detailed_logging
  }
}

# API Gateway Domain Name (for REST API)
resource "aws_api_gateway_domain_name" "domain" {
  count           = local.is_rest_api && var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  domain_name     = var.domain_name
  certificate_arn = var.domain_certificate_arn

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-domain"
      Environment = var.environment
    },
    var.tags
  )
}

# API Gateway Domain Name (for HTTP API)
resource "aws_apigatewayv2_domain_name" "http_domain" {
  count           = local.is_http_api && var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  domain_name     = var.domain_name
  
  domain_name_configuration {
    certificate_arn = var.domain_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.api_name}-domain"
      Environment = var.environment
    },
    var.tags
  )
}

# API Gateway Base Path Mapping (for REST API)
resource "aws_api_gateway_base_path_mapping" "mapping" {
  count       = local.is_rest_api && var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  api_id      = aws_api_gateway_rest_api.api[0].id
  stage_name  = aws_api_gateway_stage.stage[0].stage_name
  domain_name = aws_api_gateway_domain_name.domain[0].domain_name
  base_path   = var.base_path
}

# API Gateway Base Path Mapping (for HTTP API)
resource "aws_apigatewayv2_api_mapping" "http_mapping" {
  count       = local.is_http_api && var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  api_id      = aws_apigatewayv2_api.http_api[0].id
  stage       = aws_apigatewayv2_stage.http_stage[0].id
  domain_name = aws_apigatewayv2_domain_name.http_domain[0].domain_name
  api_mapping_key = var.base_path
}