variable "function_name" {
  description = "Name of the Lambda function to grant permissions to"
  type        = string
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  type        = string
}

variable "api_gateway_source_arn" {
  description = "Source ARN of the API Gateway route"
  type        = string
}

variable "http_methods" {
  description = "List of HTTP methods to grant permission for"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE"]
}

variable "statement_id_prefix" {
  description = "Prefix for the statement ID in the Lambda permission"
  type        = string
  default     = "AllowAPIGatewayInvoke"
} 