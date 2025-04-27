variable "domain_name" {
  description = "Custom domain name for the API Gateway"
  type        = string
  default     = null
}

variable "domain_certificate_arn" {
  description = "ARN of the ACM certificate for the custom domain"
  type        = string
  default     = null
}

# Create custom domain name if configured
resource "aws_apigatewayv2_domain_name" "domain" {
  count = var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  
  domain_name = var.domain_name
  
  domain_name_configuration {
    certificate_arn = var.domain_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  
  tags = merge(var.common_tags, {
    Name        = "${var.environment}_${var.api_name}_domain"
    Environment = var.environment
  })
}

# Create API mapping for custom domain
resource "aws_apigatewayv2_api_mapping" "domain" {
  count = var.domain_name != null && var.domain_certificate_arn != null ? 1 : 0
  
  api_id      = local.http_api_id
  domain_name = aws_apigatewayv2_domain_name.domain[0].domain_name
  stage       = var.environment
} 