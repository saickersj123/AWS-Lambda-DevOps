#!/usr/bin/env python
"""
Helper script for mocking AWS services during local integration testing.
This script sets up moto mocks for various AWS services.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Run tests with mocked AWS services"
    )
    parser.add_argument(
        "--service", 
        choices=["dynamodb", "s3", "sqs", "lambda", "all"],
        default="all",
        help="AWS service to mock (default: all)"
    )
    parser.add_argument(
        "--test-path", 
        default="tests/integration",
        help="Path to test files (default: tests/integration)"
    )
    parser.add_argument(
        "--env", 
        default="dev",
        help="Environment to use for tests (default: dev)"
    )
    parser.add_argument(
        "--mock-api",
        action="store_true",
        help="Enable API mocking (overrides MOCK_API env var)"
    )
    parser.add_argument(
        "--additional-args",
        default="",
        help="Additional pytest arguments"
    )
    
    return parser.parse_args()

def setup_mock_environment(services, mock_api=None):
    """Set up environment variables for moto mocking"""
    if services == "all" or "dynamodb" in services:
        os.environ["MOCK_DYNAMODB"] = "1"
    if services == "all" or "s3" in services:
        os.environ["MOCK_S3"] = "1"
    if services == "all" or "sqs" in services:
        os.environ["MOCK_SQS"] = "1"
    if services == "all" or "lambda" in services:
        os.environ["MOCK_LAMBDA"] = "1"
    
    # Set API mocking if specified via command line, otherwise use environment variable
    if mock_api is not None:
        os.environ["MOCK_API"] = "1" if mock_api else "0"
    
    # Print current environment settings
    print("Environment variables for mocking:")
    for key in ["MOCK_DYNAMODB", "MOCK_S3", "MOCK_SQS", "MOCK_LAMBDA", "MOCK_API"]:
        print(f"  {key}={os.environ.get(key, '0')}")
        
    # Set fake AWS credentials for moto
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-2"

def setup_python_path():
    """Set up the Python path to include the project directories"""
    # Get the project root directory
    project_root = Path(__file__).parent.parent.absolute()
    
    # Add the lambda/shared_layer/python directory to the Python path
    shared_layer_python_path = project_root / "lambda" / "shared_layer" / "python"
    if shared_layer_python_path.exists():
        sys.path.insert(0, str(shared_layer_python_path))
    
    # Add the lambda/shared_layer directory to the Python path
    shared_layer_path = project_root / "lambda" / "shared_layer"
    if shared_layer_path.exists():
        sys.path.insert(0, str(shared_layer_path))
        
    # Add the project root to the Python path
    sys.path.insert(0, str(project_root))
    
    # Print the Python path for debugging
    print(f"Project root: {project_root}")
    print(f"Python path: {sys.path[:5]}")  # Show first 5 entries in sys.path

def run_tests(test_path, env, mock_api=False, additional_args=""):
    """Run the tests with pytest"""
    # Ensure we're in the project root directory
    project_root = Path(__file__).parent.parent
    os.chdir(project_root)
    
    # Build the pytest command
    cmd = [
        sys.executable, "-m", "pytest", 
        test_path, 
        "-v", 
        f"--env={env}",
        "--junitxml=coverage_reports/mock_integration_junit.xml"
    ]
    
    # Add mock-api flag if requested
    if mock_api or os.environ.get("MOCK_API", "0") == "1":
        cmd.append("--mock-api")
    
    # Add any additional arguments
    if additional_args:
        cmd.extend(additional_args.split())
    
    print(f"Running command: {' '.join(cmd)}")
    return subprocess.run(cmd).returncode

def main():
    """Main function"""
    args = parse_args()
    
    # Set up the Python path
    setup_python_path()
    
    print("Setting up mock AWS environment...")
    # Always set MOCK_API=1 for the mock_aws_services.py script
    os.environ["MOCK_API"] = "1"
    setup_mock_environment(args.service, args.mock_api)
    
    print(f"Running tests with mocked AWS services: {args.service}")
    return run_tests(args.test_path, args.env, True, args.additional_args)  # Force mock_api=True

if __name__ == "__main__":
    sys.exit(main()) 