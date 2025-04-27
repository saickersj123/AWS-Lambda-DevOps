"""
Global test configuration for all tests.
This file sets up the Python path to include shared layers and Lambda functions.
"""

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Get the project root directory
PROJECT_ROOT = Path(__file__).parent.parent.absolute()

# Add the lambda_functions/shared_layer/python directory to the Python path
SHARED_LAYER_PYTHON_PATH = PROJECT_ROOT / "lambda_functions" / "shared_layer" / "python"
if SHARED_LAYER_PYTHON_PATH.exists():
    sys.path.insert(0, str(SHARED_LAYER_PYTHON_PATH))

# Add the lambda_functions/shared_layer directory to the Python path
SHARED_LAYER_PATH = PROJECT_ROOT / "lambda_functions" / "shared_layer"
if SHARED_LAYER_PATH.exists():
    sys.path.insert(0, str(SHARED_LAYER_PATH))

# Add each Lambda function directory to the Python path
LAMBDA_DIR = PROJECT_ROOT / "lambda_functions"
if LAMBDA_DIR.exists():
    for service_dir in LAMBDA_DIR.iterdir():
        if service_dir.is_dir() and service_dir.name != "shared_layer":
            for function_dir in service_dir.iterdir():
                if function_dir.is_dir():
                    sys.path.insert(0, str(function_dir))

# Also ensure tests directory is in the path
sys.path.insert(0, str(PROJECT_ROOT / "tests"))


@pytest.fixture(autouse=True)
def setup_test_environment():
    """Setup test environment for all tests."""
    # Set test environment variables
    with patch.dict(
        "os.environ",
        {
            "ENVIRONMENT": "test",
            "AWS_DEFAULT_REGION": "us-east-1",
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
            "AWS_SESSION_TOKEN": "test",
        },
    ):
        yield


@pytest.fixture
def mock_boto3():
    """Fixture to mock boto3 for all tests."""
    with patch("boto3") as mock:
        yield mock


@pytest.fixture
def mock_dynamodb(mock_boto3):
    """Fixture to mock DynamoDB for all tests."""
    mock_table = MagicMock()
    mock_boto3.resource.return_value.Table.return_value = mock_table
    return mock_table


# Add some debugging output that will be visible when running tests
print(f"Project root: {PROJECT_ROOT}")
print(f"Python path: {sys.path[:5]}")  # Show first 5 entries in sys.path
