# Create zip files for Lambda functions
data "archive_file" "lambda_zip" {
  for_each = var.function_configs
  
  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.root}/build/${each.value.name}.zip"
}

# Create Lambda functions
resource "aws_lambda_function" "functions" {
  for_each = var.function_configs

  filename         = data.archive_file.lambda_zip[each.key].output_path
  # Use both the archive hash and the externally provided source_code_hash to detect changes
  source_code_hash = try(
    each.value.source_code_hash != null ? each.value.source_code_hash : data.archive_file.lambda_zip[each.key].output_base64sha256, 
    data.archive_file.lambda_zip[each.key].output_base64sha256
  )
  function_name   = "${var.environment}_${each.key}"
  role            = aws_iam_role.lambda_role[each.key].arn
  handler         = each.value.handler
  runtime         = each.value.runtime
  timeout         = try(each.value.timeout, 30)
  memory_size     = try(each.value.memory_size, 128)

  dynamic "environment" {
    for_each = length(try(each.value.environment_variables, {})) > 0 ? [1] : []
    content {
      variables = each.value.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = merge(var.common_tags, {
    Name        = var.environment == "prod" ? each.key : "${var.environment}_${each.key}"
    Service     = each.value.service_name
    Environment = var.environment
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}