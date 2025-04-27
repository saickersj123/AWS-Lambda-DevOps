provider "aws" {
  region = var.region
}

# Remote state and locking configuration
terraform {
  backend "s3" {
    bucket         = "aws-lambda-tf-state-bucket"
    key            = "jenkins/terraform.tfstate"
    region         = "us-east-2"
    use_lockfile   = true
    encrypt        = true
  }
}

# VPC and Network Resources for Jenkins
module "vpc" {
  source = "../modules/vpc"
  
  environment = var.environment
  vpc_cidr    = "10.1.0.0/16"
  
  public_subnet_cidrs  = ["10.1.101.0/24", "10.1.102.0/24"]
  private_subnet_cidrs = []
  availability_zones   = ["us-east-2a", "us-east-2b"]
  enable_nat_gateway   = false
  
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# S3 Bucket for Jenkins artifacts
resource "aws_s3_bucket" "jenkins_artifacts" {
  bucket        = "jenkins-artifacts-pandacharging"
  force_destroy = true

  tags = {
    Name        = "jenkins-artifacts"
    Environment = var.environment
  }
}

# Set bucket ownership controls instead of ACL
resource "aws_s3_bucket_ownership_controls" "jenkins_artifacts_ownership" {
  bucket = aws_s3_bucket.jenkins_artifacts.id
  
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Jenkins CI/CD Server
module "jenkins" {
  source = "../modules/jenkins"
  
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.public_subnet_ids[0]
  key_name    = var.key_name
  
  region              = var.region
  private_key_path   = var.private_key_path
  instance_type      = var.instance_type
  volume_size        = var.volume_size
  jenkins_access_cidr = var.jenkins_access_cidr
  ssh_access_cidr    = var.ssh_access_cidr
  
  jenkins_admin_username = var.jenkins_admin_username
  jenkins_admin_password = var.jenkins_admin_password
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}

# Output the Jenkins URL and other information
output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = module.jenkins.jenkins_url
} 