# Import the helper module to configure AWS environment variables
import json
import os
import sys
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest

# Get the project root directory
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))

# Add necessary paths to sys.path
sys.path.insert(0, PROJECT_ROOT)
sys.path.insert(0, os.path.join(PROJECT_ROOT, "lambda_functions"))
sys.path.insert(
    0, os.path.join(PROJECT_ROOT, "lambda_functions", "shared_layer", "python")
)
sys.path.insert(
    0, os.path.join(PROJECT_ROOT, "lambda_functions", "device", "device_status")
)

# Import the module after setting up the path
from device.device_status.index import (
    get_current_timestamp,
    get_device_status,
    lambda_handler,
    update_device_status,
    validate_device_id,
)

# Ensure environment is configured
from import_helper import configure_aws_environment

configure_aws_environment()

# Import will happen after AWS services are mocked by the fixtures
# We'll import inside each test or use patch to mock the module


@pytest.fixture
def mock_device_table():
    """Fixture to mock the DynamoDB table."""
    with patch("device.device_status.index.device_table") as mock:
        yield mock


@pytest.fixture
def mock_logger():
    """Fixture to mock the logger."""
    with patch("device.device_status.index.logger") as mock:
        yield mock


@pytest.fixture
def sample_get_event():
    """Sample API Gateway event for GET request"""
    return {"httpMethod": "GET", "pathParameters": {"device_id": "test-device-1"}}


@pytest.fixture
def sample_update_event():
    """Sample API Gateway event for POST request"""
    return {
        "httpMethod": "POST",
        "body": json.dumps(
            {"device_id": "test-device-1", "status": "inactive", "battery_level": 75}
        ),
    }


def test_lambda_handler_post(mock_device_table, mock_logger):
    """Test lambda_handler with POST method."""
    event = {
        "httpMethod": "POST",
        "body": '{"device_id": "dev-123", "status": "active"}',
    }
    mock_device_table.put_item.return_value = {}

    response = lambda_handler(event, {})

    assert response["statusCode"] == 200
    mock_logger.info.assert_called()
    mock_device_table.put_item.assert_called_once()


def test_lambda_handler_get(mock_device_table, mock_logger):
    """Test lambda_handler with GET method."""
    event = {"httpMethod": "GET", "pathParameters": {"device_id": "dev-123"}}
    mock_device_table.get_item.return_value = {
        "Item": {"device_id": "dev-123", "status": "active"}
    }

    response = lambda_handler(event, {})

    assert response["statusCode"] == 200
    mock_logger.info.assert_called()
    mock_device_table.get_item.assert_called_once()


def test_lambda_handler_invalid_method(mock_device_table, mock_logger):
    """Test lambda_handler with invalid HTTP method."""
    event = {"httpMethod": "PUT"}

    response = lambda_handler(event, {})

    assert response["statusCode"] == 400
    assert "error" in response["body"]


def test_update_device_status_missing_fields():
    """Test update_device_status with missing required fields."""
    event = {"body": '{"device_id": "dev-123"}'}  # Missing status

    response = update_device_status(event)

    assert response["statusCode"] == 400
    assert "Missing required field" in response["body"]


def test_update_device_status_success(mock_device_table, mock_logger):
    """Test successful device status update."""
    event = {
        "body": '{"device_id": "dev-123", "status": "active", "battery_level": 80}'
    }

    response = update_device_status(event)

    assert response["statusCode"] == 200
    mock_device_table.put_item.assert_called_once()
    assert "battery_level" in mock_device_table.put_item.call_args[1]["Item"]


def test_get_device_status_not_found(mock_device_table):
    """Test get_device_status when device is not found."""
    event = {"pathParameters": {"device_id": "dev-123"}}
    mock_device_table.get_item.return_value = {}

    response = get_device_status(event)

    assert response["statusCode"] == 404
    assert "Device not found" in response["body"]


def test_get_device_status_success(mock_device_table):
    """Test successful device status retrieval."""
    event = {"pathParameters": {"device_id": "dev-123"}}
    mock_device_table.get_item.return_value = {
        "Item": {"device_id": "dev-123", "status": "active"}
    }

    response = get_device_status(event)

    assert response["statusCode"] == 200
    assert response["body"] == '{"device_id": "dev-123", "status": "active"}'


def test_validate_device_id():
    """Test device ID validation."""
    # Valid cases
    assert validate_device_id("dev-123") is True
    assert validate_device_id("dev-abc123") is True

    # Invalid cases
    assert validate_device_id("") is False
    assert validate_device_id("dev-") is False
    assert validate_device_id("invalid") is False
    assert validate_device_id(None) is False
    assert validate_device_id(123) is False


def test_get_current_timestamp():
    """Test timestamp generation."""
    with patch("datetime.datetime") as mock_datetime:
        mock_now = datetime(2024, 1, 1, tzinfo=UTC)
        mock_datetime.now.return_value = mock_now

        timestamp = get_current_timestamp()

        assert timestamp == "2024-01-01T00:00:00+00:00"
        mock_datetime.now.assert_called_once_with(UTC)


def test_update_device_status_with_optional_fields(mock_device_table, mock_logger):
    """Test device status update with all optional fields."""
    event = {
        "body": json.dumps(
            {
                "device_id": "dev-123",
                "status": "active",
                "battery_level": 80,
                "connection_strength": "strong",
                "firmware_version": "1.0.0",
            }
        )
    }

    response = update_device_status(event)

    assert response["statusCode"] == 200
    mock_device_table.put_item.assert_called_once()
    item = mock_device_table.put_item.call_args[1]["Item"]
    assert item["battery_level"] == 80
    assert item["connection_strength"] == "strong"
    assert item["firmware_version"] == "1.0.0"
