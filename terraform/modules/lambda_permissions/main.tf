# Lambda Permissions Module
# This module creates permissions for Lambda to be invoked by API Gateway
# It's separated from the Lambda and API Gateway modules to break circular dependencies

# Grant API Gateway permission to invoke Lambda functions
resource "aws_lambda_permission" "api_gateway" {
  for_each = toset(var.http_methods)

  statement_id  = "${var.statement_id_prefix}_${each.value}"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Allow invocation from specific API Gateway route
  source_arn = var.api_gateway_source_arn
} 