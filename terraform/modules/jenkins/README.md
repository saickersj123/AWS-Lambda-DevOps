# Jenkins Terraform Module

This Terraform module deploys a Jenkins server on AWS with automated security configuration and plugin installation.

## Features

- Automated Jenkins installation with Docker
- Security configuration via init.groovy.d scripts
- Pre-installed essential plugins
- Secure by default (including IMDSv2 enforcement)
- IAM role and policies for AWS service interactions
- Ready for AWS Lambda deployment pipeline setup

## Usage

```hcl
module "jenkins" {
  source = "./modules/jenkins"
  
  region      = "us-east-2"
  environment = "dev"
  
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]
  
  key_name         = "jenkins-key"  # AWS key pair name
  private_key_path = "~/.ssh/jenkins-key.pem"  # Local path to private key
  
  jenkins_admin_username = "admin"
  jenkins_admin_password = "StrongPassword123"  # Use secrets manager in production
}
```

## Pre-requisites

1. AWS account with appropriate permissions
2. AWS key pair for SSH access
3. VPC and subnet configured
4. Terraform installed (version 1.0.0+)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | string | `"us-east-2"` | no |
| environment | Environment (dev, staging, prod) | string | n/a | yes |
| vpc_id | VPC ID where Jenkins will be deployed | string | n/a | yes |
| subnet_id | Subnet ID where Jenkins will be deployed | string | n/a | yes |
| key_name | AWS EC2 key pair name | string | n/a | yes |
| private_key_path | Path to the private key file for SSH connections | string | n/a | yes |
| instance_type | EC2 instance type for Jenkins server | string | `"t2.micro"` | no |
| volume_size | Size of the Jenkins server root volume in GB | number | `30` | no |
| jenkins_access_cidr | CIDR blocks allowed to access Jenkins UI | list(string) | `["0.0.0.0/0"]` | no |
| ssh_access_cidr | CIDR blocks allowed to SSH into Jenkins | list(string) | `["0.0.0.0/0"]` | no |
| jenkins_admin_username | Jenkins admin username | string | `"admin"` | no |
| jenkins_admin_password | Jenkins admin password | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| jenkins_public_ip | The public IP of the Jenkins server |
| jenkins_url | URL to access Jenkins |
| jenkins_instance_id | Instance ID of the Jenkins server |
| jenkins_security_group_id | Security group ID of the Jenkins server |
| jenkins_setup_command | Command to check Jenkins setup status |
| jenkins_status | Information about Jenkins configuration status |

## Jenkins Configuration

This module uses init.groovy.d scripts to automate the setup of Jenkins security. The configuration includes:

- Security settings
- Admin user creation
- Plugin installation

### Default Plugins Installed

- workflow-aggregator (Pipeline)
- git
- aws-credentials
- pipeline-aws
- pipeline-stage-view
- blueocean
- docker-workflow
- credentials-binding
- and many more...

## SSH Access

To SSH into the Jenkins instance:

```bash
ssh -i /path/to/your/key.pem ec2-user@<jenkins_public_ip>
```

## Checking Jenkins Setup Status

```bash
ssh -i /path/to/your/key.pem ec2-user@<jenkins_public_ip> 'cat /tmp/jenkins_setup.log'
```

## Troubleshooting

If Jenkins setup doesn't apply correctly:

1. SSH into the Jenkins instance
2. Check the logs: `cat /tmp/jenkins_setup.log`
3. Check Jenkins logs: `docker logs jenkins`
4. Verify if the init.groovy.d scripts are in place: `ls -la /var/jenkins_home/init.groovy.d/`

## Security Considerations

For production use:

1. Restrict `jenkins_access_cidr` and `ssh_access_cidr` to your IP or VPN network
2. Use AWS Secrets Manager for sensitive data like passwords
3. Enable HTTPS by setting up an Application Load Balancer with TLS
4. Consider using a private subnet with a bastion host
5. IMDSv2 is enforced by default for enhanced security

## License

This module is open source and available under the MIT license. 