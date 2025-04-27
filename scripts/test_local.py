#!/usr/bin/env python
"""
Simple script to run tests locally with mocked AWS services.
"""

import os
import sys
import subprocess
from pathlib import Path

def main():
    """Main function to run tests locally."""
    # Set up environment variables for mocking
    os.environ["MOCK_DYNAMODB"] = "1"
    os.environ["MOCK_S3"] = "1"
    os.environ["MOCK_SQS"] = "1"
    os.environ["MOCK_LAMBDA"] = "1"
    
    # Set fake AWS credentials
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-2"
    
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
    
    # Run unit tests
    print("\n=== Running Unit Tests ===\n")
    unit_result = subprocess.run(
        [sys.executable, "-m", "pytest", "tests/unit", "-v"],
        cwd=project_root
    )
    
    return unit_result.returncode

if __name__ == "__main__":
    sys.exit(main()) 