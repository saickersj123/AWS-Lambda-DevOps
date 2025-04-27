# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = var.enable_cloudwatch_logs ? var.function_configs : {}
  
  name              = "/aws/lambda/${var.environment}_${each.key}"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.common_tags, {
    Name        = var.environment == "prod" ? "${each.key}_logs" : "${var.environment}_${each.key}_logs"
    Service     = each.value.service_name
    Environment = var.environment
  })
}

# Local for log group ARNs
locals {
  log_group_arns = {
    for k, v in aws_cloudwatch_log_group.lambda_log_group : k => v.arn
  }
} 