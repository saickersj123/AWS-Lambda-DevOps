"""
Unit test configuration.
This file provides fixtures for unit tests to mock AWS services.
"""

import os
from unittest.mock import patch

import pytest
from moto import mock_aws

# Make sure AWS region is set for tests
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-2")


@pytest.fixture(scope="function", autouse=True)
def mock_env_variables():
    """Mock environment variables for tests."""
    with patch.dict(
        "os.environ",
        {
            "ENVIRONMENT": "test",
            "AWS_DEFAULT_REGION": "us-east-2",
            "AWS_ACCESS_KEY_ID": "testing",
            "AWS_SECRET_ACCESS_KEY": "testing",
            "AWS_SECURITY_TOKEN": "testing",
            "AWS_SESSION_TOKEN": "testing",
        },
    ):
        yield


@pytest.fixture(scope="function")
def mock_aws_services():
    """Mock all AWS services used in tests."""
    with mock_aws():
        yield
