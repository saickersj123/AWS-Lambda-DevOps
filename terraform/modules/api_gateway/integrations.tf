# Get current AWS region and account ID
data "aws_region" "current" {}

# Get AWS account ID
data "aws_caller_identity" "current" {}

# Create Lambda integrations for each unique function
resource "aws_apigatewayv2_integration" "lambda" {
  for_each = {
    for k, v in var.routes : v.function_name => v...
  }
  
  api_id                 = local.http_api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.environment == "prod" ? each.key : "${var.environment}_${each.key}"}"
  payload_format_version = "2.0"
  description           = "Lambda integration for ${each.key}"
  
  timeout_milliseconds = try(var.integration_timeout_milliseconds, 30000)
} 