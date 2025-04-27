output "layer_arn" {
  description = "ARN of the Lambda layer"
  value       = aws_lambda_layer_version.layer.arn
}

output "layer_version" {
  description = "Version of the Lambda layer"
  value       = aws_lambda_layer_version.layer.version
}

output "layer_name" {
  description = "Name of the Lambda layer"
  value       = aws_lambda_layer_version.layer.layer_name
}

output "layer_source_code_hash" {
  description = "Base64-encoded representation of the layer's source code hash"
  value       = aws_lambda_layer_version.layer.source_code_hash
}

output "layer_description" {
  description = "Description of the Lambda layer"
  value       = aws_lambda_layer_version.layer.description
}

output "layer_compatible_runtimes" {
  description = "List of compatible Lambda runtimes"
  value       = aws_lambda_layer_version.layer.compatible_runtimes
}

output "layer_compatible_architectures" {
  description = "List of compatible Lambda architectures"
  value       = aws_lambda_layer_version.layer.compatible_architectures
} 