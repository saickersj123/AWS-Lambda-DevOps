# Testing Guide

This guide provides comprehensive instructions for testing AWS Lambda functions and infrastructure, both locally and in CI/CD pipelines.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Test Types and Execution](#test-types-and-execution)
4. [AWS Service Mocking](#aws-service-mocking)
5. [Infrastructure Testing](#infrastructure-testing)
6. [CI/CD Pipeline Testing](#cicd-pipeline-testing)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Prerequisites

- Python 3.11+
- Virtual environment (`venv`)
- AWS credentials (for integration tests)
- Terraform (for infrastructure testing)

## Environment Setup

1. Clone and initialize the repository:
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ./scripts/setup_dev_environment.sh
   ```

2. Configure AWS credentials (for integration tests):
   ```bash
   # Using environment variables
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_DEFAULT_REGION=us-east-2

   # Or using AWS CLI
   aws configure
   ```

## Test Types and Execution

### Unit Tests
Unit tests verify code functionality without external dependencies.

```bash
# Run all unit tests
./scripts/run_unit_tests.sh

# Run specific tests
./scripts/run_unit_tests.sh tests/unit/device/test_device_status.py
./scripts/run_unit_tests.sh tests/unit/device/test_device_status.py::test_get_device_status

# Run with coverage
python -m pytest tests/unit -v --cov=lambda_functions --cov-report=term-missing
```

### Integration Tests
Integration tests validate interactions with AWS services.

```bash
# Run all integration tests (dev environment)
./scripts/run_integration_tests.sh

# Run against staging
./scripts/run_integration_tests.sh staging

# Run specific tests
./scripts/run_integration_tests.sh dev tests/integration/device/
```

### All Tests
Run both unit and integration tests:
```bash
./scripts/run_all_tests.sh [environment]
```

## AWS Service Mocking

For local development without real AWS credentials:

```bash
# Mock all services
./scripts/run_mock_tests.sh

# Mock specific services
./scripts/run_mock_tests.sh staging dynamodb
./scripts/run_mock_tests.sh dev s3 tests/integration/device/test_device_status_integration.py
```

Available mock options:
- `all` - All AWS services
- `dynamodb` - DynamoDB
- `s3` - S3
- `sqs` - SQS
- `lambda` - Lambda

## Infrastructure Testing

### Terraform Testing
```bash
cd terraform/environments/dev
terraform init
terraform validate
terraform plan
```

### Testing Infrastructure Changes
1. Modify Terraform configuration
2. Run `terraform plan`
3. Execute integration tests
4. Apply changes if tests pass

## CI/CD Pipeline Testing

The pipeline automatically runs:
1. Linting (pylint, black)
2. Unit tests with coverage
3. Integration tests
4. Terraform validation

### Pipeline Configuration
- Environment selection (dev/staging/prod)
- Coverage reporting (Cobertura)
- Test reporting (JUnit XML)
- Notifications (Slack/email)

### Skipping Tests
```bash
./jenkins-build.sh --skip-tests
./jenkins-build.sh --skip-integration-tests
```

## Troubleshooting

### Common Issues

1. **Import Errors**
   - Ensure Python path includes:
     - Project root
     - `lambda_functions/shared_layer`
     - `lambda_functions/shared_layer/python`

2. **AWS Credential Errors**
   - Verify AWS credentials configuration
   - Use mocked services for development

3. **Slow Tests**
   - Run only unit tests during development
   - Use specific test files
   - Leverage mocked services

4. **CI/CD Failures**
   - Match local environment with CI/CD
   - Check for hardcoded values
   - Verify infrastructure state

## Best Practices

1. **Development Workflow**
   ```bash
   # 1. Start development
   git checkout -b feature/new-feature

   # 2. Run unit tests
   ./scripts/run_unit_tests.sh

   # 3. Run mocked integration tests
   ./scripts/run_mock_tests.sh

   # 4. Run real integration tests
   ./scripts/run_integration_tests.sh dev

   # 5. Commit and push
   git add .
   git commit -m "Add new feature"
   git push origin feature/new-feature
   ```

2. **Testing Guidelines**
   - Write tests first (TDD)
   - Keep tests independent
   - Mock external dependencies
   - Test edge cases
   - Maintain 80%+ coverage
   - Test infrastructure changes
   - Isolate test data between environments 