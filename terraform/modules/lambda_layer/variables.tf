variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "layer_name" {
  description = "Name of the Lambda layer"
  type        = string
}

variable "compatible_runtimes" {
  description = "List of compatible Lambda runtimes"
  type        = list(string)
  default     = ["python3.8", "python3.9", "python3.10", "python3.11"]
}

variable "source_path" {
  description = "Path to the layer's source code"
  type        = string
}

variable "description" {
  description = "Description of the Lambda layer"
  type        = string
  default     = "Common utilities layer"
}

variable "compatible_architectures" {
  description = "List of compatible Lambda architectures"
  type        = list(string)
  default     = ["x86_64"]
}

variable "skip_destroy" {
  description = "Whether to retain the old layer version when a new one is created"
  type        = bool
  default     = false
}

variable "enable_resource_tagging" {
  description = "Whether to enable resource tagging using AWS Resource Groups Tagging API"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
} 