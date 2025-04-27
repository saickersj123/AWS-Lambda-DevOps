variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "shared"
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
  default     = "jenkins-key"
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
  default     = "~/.ssh/jenkins-key.pem"
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "volume_size" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 30
}

variable "jenkins_access_cidr" {
  description = "CIDR blocks that can access Jenkins web interface"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Consider restricting this in production
}

variable "ssh_access_cidr" {
  description = "CIDR blocks that can SSH into Jenkins"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Consider restricting this in production
}

variable "jenkins_admin_username" {
  description = "Jenkins admin username"
  type        = string
  default     = "admin"
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
} 