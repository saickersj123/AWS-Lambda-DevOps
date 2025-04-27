# Cost-Optimized VPC Module

This Terraform module creates a VPC with cost-optimized networking configuration. It implements several strategies to reduce AWS costs while maintaining security and functionality.

## Cost-Saving Features

1. **Environment-Based NAT Strategy**:
   - Production environment: Uses NAT Gateway for high availability
   - Non-production environments: Uses NAT Instance for cost savings
   - Single NAT Gateway/Instance per VPC instead of per subnet

2. **VPC Endpoints**:
   - S3 and DynamoDB endpoints to eliminate NAT Gateway costs for AWS service access
   - Reduces data transfer costs for AWS service access

3. **Optimized Subnet Design**:
   - Separate public and private subnets
   - Proper tagging for cost allocation
   - Efficient CIDR block allocation

## Usage

```hcl
module "vpc" {
  source = "./modules/vpc"

  environment = "dev"  # or "staging" or "prod"
  vpc_cidr    = "10.0.0.0/16"

  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
  availability_zones   = ["us-east-2a", "us-east-2b"]

  common_tags = {
    Project     = "my-project"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name (dev, staging, prod) | string | n/a | yes |
| vpc_cidr | CIDR block for the VPC | string | n/a | yes |
| public_subnet_cidrs | List of CIDR blocks for public subnets | list(string) | n/a | yes |
| private_subnet_cidrs | List of CIDR blocks for private subnets | list(string) | n/a | yes |
| availability_zones | List of availability zones to use | list(string) | n/a | yes |
| common_tags | Common tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| public_subnet_ids | IDs of the public subnets |
| private_subnet_ids | IDs of the private subnets |
| nat_gateway_id | ID of the NAT Gateway (if in production) |
| nat_instance_id | ID of the NAT Instance (if not in production) |
| vpc_endpoint_s3_id | ID of the S3 VPC endpoint |
| vpc_endpoint_dynamodb_id | ID of the DynamoDB VPC endpoint |

## Cost Comparison

### Before Optimization
- Multiple VPCs (one per environment)
- NAT Gateway per subnet
- No VPC endpoints
- Estimated monthly cost: ~$200-300 per environment

### After Optimization
- Single VPC with environment isolation
- NAT Gateway only in production, NAT Instance in non-production
- VPC endpoints for AWS services
- Estimated monthly cost: ~$50-100 per environment

## Security Considerations

1. **NAT Instance Security**:
   - Security group restricts inbound traffic to private subnets only
   - Outbound traffic allowed to internet
   - Regular security updates required

2. **VPC Endpoints**:
   - Gateway endpoints for S3 and DynamoDB
   - No additional security groups required
   - Private connectivity to AWS services

3. **Subnet Isolation**:
   - Public subnets for internet-facing resources
   - Private subnets for internal resources
   - Proper security group rules for each tier

## Maintenance

1. **NAT Instance Updates**:
   - Regular AMI updates required
   - Security patches should be applied
   - Consider using AWS Systems Manager for maintenance

2. **VPC Endpoints**:
   - No maintenance required
   - Automatically updated by AWS

## License

This module is open source and available under the MIT license. 