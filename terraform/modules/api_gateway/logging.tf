# Create CloudWatch log group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.environment}_${var.api_name}"
  retention_in_days = var.access_log_settings.retention_days
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}_${var.api_name}_logs"
  })
} 