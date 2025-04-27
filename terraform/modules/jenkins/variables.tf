variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Jenkins will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where Jenkins will be deployed"
  type        = string
}

variable "key_name" {
  description = "EC2 Key for Jenkins Server"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file for SSH connections"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t2.micro"
}

variable "volume_size" {
  description = "Size of the Jenkins server root volume in GB"
  type        = number
  default     = 15
}

variable "jenkins_access_cidr" {
  description = "CIDR blocks allowed to access Jenkins UI"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_access_cidr" {
  description = "CIDR blocks allowed to SSH into Jenkins"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
  description = "AWS Access Key ID for Jenkins"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key for Jenkins"
  type        = string
  sensitive   = true
}

variable "jcasc_config_path" {
  description = "Path to the JCasC configuration file template"
  type        = string
  default     = ""
}

variable "github_repo_url" {
  description = "GitHub repository URL for the Jenkinsfile"
  type        = string
  default     = "https://github.com/panda-charging/aws"
}
