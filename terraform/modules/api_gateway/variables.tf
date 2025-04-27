variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "api_gateway_type" {
  description = "Type of API Gateway to create (REST or HTTP)"
  type        = string
  default     = "REST"
  validation {
    condition     = contains(["REST", "HTTP"], var.api_gateway_type)
    error_message = "API Gateway type must be either REST or HTTP."
  }
}

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "description" {
  description = "Description of the API Gateway"
  type        = string
  default     = "API Gateway created by Terraform"
}

variable "use_existing_api" {
  description = "Whether to use an existing API Gateway instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_api_id" {
  description = "ID of the existing API Gateway to use (if use_existing_api is true)"
  type        = string
  default     = ""
}

variable "endpoint_type" {
  description = "Endpoint type for API Gateway (EDGE, REGIONAL, or PRIVATE)"
  type        = string
  default     = "REGIONAL"
}

variable "endpoints" {
  description = "Map of API Gateway endpoints and their configuration"
  type = map(object({
    path           = string
    methods        = optional(list(string), ["GET"])
    function_name  = string
    service_name   = optional(string)
    handler        = optional(string, "index.handler")
  }))
  default = {}
}

variable "log_retention_days" {
  description = "CloudWatch Log Group retention in days"
  type        = number
  default     = 14
}

variable "access_log_format" {
  description = "Format of access logs for REST API Gateway"
  type        = string
  default     = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\" }"
}

variable "http_access_log_format" {
  description = "Format of access logs for HTTP API Gateway"
  type        = any
  default     = {
    requestId      = "$context.requestId"
    ip             = "$context.identity.sourceIp"
    requestTime    = "$context.requestTime"
    httpMethod     = "$context.httpMethod"
    routeKey       = "$context.routeKey"
    status         = "$context.status"
    protocol       = "$context.protocol"
    responseLength = "$context.responseLength"
  }
}

variable "enable_detailed_logging" {
  description = "Enable detailed CloudWatch logging for API Gateway"
  type        = bool
  default     = false
}

variable "base_path" {
  description = "Base path mapping for the custom domain"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "additional_stages" {
  description = "Map of additional stages to create, where key is the stage name"
  type = map(object({
    variables = optional(map(string), {})
    enable_detailed_logging = optional(bool)
    throttling_burst_limit = optional(number)
    throttling_rate_limit = optional(number)
    caching_enabled = optional(bool)
    domain_mapping_enabled = optional(bool, false)
    base_path = optional(string)
  }))
  default = {}
}

variable "resource_paths" {
  description = "List of resource path parts to create in the API Gateway"
  type        = list(string)
  default     = []
}

variable "resource_parent_ids" {
  description = "List of parent resource IDs for each resource path (optional)"
  type        = list(string)
  default     = null
}

variable "http_methods" {
  description = "List of HTTP methods to create (GET, POST, etc.)"
  type        = list(string)
  default     = []
}

variable "method_resource_ids" {
  description = "List of resource IDs to attach methods to (optional)"
  type        = list(string)
  default     = null
}

variable "authorization_type" {
  description = "Authorization type for API methods (NONE, AWS_IAM, CUSTOM, COGNITO_USER_POOLS)"
  type        = string
  default     = "NONE"
}

variable "authorizer_id" {
  description = "ID of the authorizer to use with the method (if applicable)"
  type        = string
  default     = null
}

variable "lambda_invoke_arns" {
  description = "List of Lambda invoke ARNs to integrate with each method"
  type        = list(string)
  default     = []
}

variable "skip_lambda_permissions" {
  description = "Set to true to skip creating Lambda permissions, useful when Lambda functions don't exist yet"
  type        = bool
  default     = false
}

variable "cors_configuration" {
  description = "CORS configuration for the API Gateway"
  type = object({
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age          = number
    allow_credentials = bool
  })
  default = {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
    expose_headers    = []
    max_age          = 7200
    allow_credentials = false
  }
}

variable "routes" {
  description = "Map of API routes and their configurations"
  type = map(object({
    path           = string
    methods        = list(string)
    function_name  = string
    authorization  = optional(string, "NONE")
    authorizer_id  = optional(string)
  }))
}

variable "stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "$default"
}

variable "access_log_settings" {
  description = "Access log settings for the API Gateway"
  type = object({
    retention_days = number
    format        = string
  })
  default = {
    retention_days = 7
    format        = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\", \"integrationError\":\"$context.integrationErrorMessage\" }"
  }
}

variable "throttling_settings" {
  description = "Throttling settings for the API Gateway"
  type = object({
    burst_limit = number
    rate_limit  = number
  })
  default = {
    burst_limit = 5000
    rate_limit  = 10000
  }
}

variable "integration_timeout_milliseconds" {
  description = "Timeout in milliseconds for Lambda integration"
  type        = number
  default     = 30000
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_log_group" {
  description = "Whether to create a CloudWatch Log Group for API Gateway logs"
  type        = bool
  default     = true
}