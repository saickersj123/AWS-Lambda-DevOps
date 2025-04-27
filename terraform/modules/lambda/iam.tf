# Create IAM roles for Lambda functions
resource "aws_iam_role" "lambda_role" {
  for_each = var.function_configs
  
  name = var.environment == "prod" ? "${each.key}_role" : "${var.environment}_${each.key}_role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name        = var.environment == "prod" ? "${each.key}_role" : "${var.environment}_${each.key}_role"
    Service     = each.value.service_name
    Environment = var.environment
  })
  
  # Handle existing roles
  lifecycle {
    ignore_changes = [name]
  }
}

# Basic Lambda execution policy (CloudWatch logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  for_each = var.enable_cloudwatch_logs ? var.function_configs : {}
  
  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC access policy for Lambda functions
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  for_each = var.vpc_config != null ? var.function_configs : {}
  
  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  for_each = var.enable_xray_tracing ? var.function_configs : {}
  
  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Additional IAM policies
resource "aws_iam_role_policy" "additional_policies" {
  for_each = var.additional_policies
  
  name   = each.value.name
  role   = aws_iam_role.lambda_role[each.key].id
  policy = each.value.policy_json
} 