variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "function_configs" {
  description = "Map of function configurations from function.json files"
  type = map(object({
    name                = string
    source_dir          = string
    config_hash         = optional(string)
    source_code_hash    = optional(string)
    api_path           = optional(string)
    api_methods        = optional(list(string))
    service_name       = string
    handler            = string
    runtime            = string
    timeout            = optional(number, 30)
    memory_size        = optional(number, 128)
    environment_variables = optional(map(string), {})
    layers             = optional(list(string), [])
    architectures      = optional(list(string), ["x86_64"])
    reserved_concurrent_executions = optional(number, -1)
    dead_letter_config = optional(object({
      target_arn = string
    }))
    ephemeral_storage = optional(object({
      size = number
    }))
  }))
}

variable "vpc_config" {
  description = "VPC configuration for Lambda functions"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Whether to enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain Lambda function logs"
  type        = number
  default     = 14
}

variable "additional_policies" {
  description = "Map of additional IAM policies to attach to Lambda roles"
  type = map(object({
    name        = string
    policy_json = string
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
} 