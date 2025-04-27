terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data sources
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security group for Jenkins
resource "aws_security_group" "jenkins" {
  name        = "${var.environment}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP access to Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.jenkins_access_cidr
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_access_cidr
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-jenkins-sg"
    Environment = var.environment
  }
}

# IAM role for Jenkins
resource "aws_iam_role" "jenkins" {
  name = "${var.environment}-jenkins-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
    }]
  })
  
  tags = {
    Name        = "${var.environment}-jenkins-role"
    Environment = var.environment
  }
}

# IAM instance profile
resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# Jenkins EC2 instance
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_name
  subnet_id             = var.subnet_id
  iam_instance_profile  = aws_iam_instance_profile.jenkins.name
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  
  # Require IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # This enforces IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/templates/user_data.sh", {
    jenkins_admin_username = var.jenkins_admin_username
    jenkins_admin_password = var.jenkins_admin_password
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    region               = var.region
    environment         = var.environment
  })

  tags = {
    Name        = "${var.environment}-jenkins"
    Environment = var.environment
  }
}