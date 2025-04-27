output "function_arns" {
  description = "ARNs of created Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.arn
  }
}

output "function_names" {
  description = "Names of created Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.function_name
  }
}

output "function_roles" {
  description = "IAM roles created for Lambda functions"
  value = {
    for k, v in aws_iam_role.lambda_role : k => v.arn
  }
}

output "function_invoke_arns" {
  description = "Invoke ARNs of created Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.invoke_arn
  }
}

output "function_qualified_arns" {
  description = "Qualified ARNs of created Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.qualified_arn
  }
}

output "function_versions" {
  description = "Latest published versions of Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.version
  }
}

output "log_group_arns" {
  description = "ARNs of CloudWatch Log Groups for Lambda functions"
  value = local.log_group_arns
}

output "function_last_modified" {
  description = "Last modified timestamps of Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.last_modified
  }
}

output "function_source_code_hashes" {
  description = "Source code hashes of Lambda functions"
  value = {
    for k, v in aws_lambda_function.functions : k => v.source_code_hash
  }
} 