# Create zip file for the Lambda layer
data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = var.source_path
  output_path = "${path.root}/build/${var.layer_name}.zip"
}

# Create Lambda layer
resource "aws_lambda_layer_version" "layer" {
  filename            = data.archive_file.layer_zip.output_path
  layer_name         = "${var.environment}_${var.layer_name}"
  description        = var.description
  compatible_runtimes = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures
  skip_destroy       = var.skip_destroy
  
  source_code_hash = data.archive_file.layer_zip.output_base64sha256
}

# Add resource tags using AWS resource tags API
resource "aws_resourcegroupstaggingapi_resources" "layer_tags" {
  count = var.enable_resource_tagging ? 1 : 0
  
  tags_by_resource_arn = {
    "${aws_lambda_layer_version.layer.arn}" = merge(var.common_tags, {
      Name        = "${var.environment}_${var.layer_name}"
      Environment = var.environment
    })
  }
} 