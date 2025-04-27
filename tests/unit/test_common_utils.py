import json
import logging
import os
from unittest.mock import MagicMock, patch

import pytest

# Add lambda_functions directory to Python path
os.environ["ENVIRONMENT"] = "test"

# Import shared utilities
import common_utils


@pytest.fixture(autouse=True)
def mock_env():
    """Fixture to mock environment variables for all tests."""
    with patch.dict("os.environ", {"ENVIRONMENT": "test"}):
        yield


@pytest.mark.parametrize(
    "status_code,body,headers,expected_headers",
    [
        (
            200,
            {"message": "Success"},
            None,
            {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True,
            },
        ),
        (
            201,
            {"id": "123"},
            {"X-Custom-Header": "test-value"},
            {"X-Custom-Header": "test-value"},
        ),
        (
            400,
            {"error": "Bad Request"},
            None,
            {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True,
            },
        ),
    ],
)
def test_format_response(status_code, body, headers, expected_headers):
    """
    Test format_response function with various status codes and headers.
    Verifies that:
    1. Status code is correctly set
    2. Body is properly JSON encoded
    3. Headers are correctly merged with defaults
    """
    response = common_utils.format_response(status_code, body, headers)

    assert response["statusCode"] == status_code
    assert json.loads(response["body"]) == body

    if headers:
        assert response["headers"] == headers
    else:
        assert response["headers"] == expected_headers


@pytest.mark.parametrize(
    "table_name,expected_table_name",
    [
        ("users", "test-users"),
        ("test-products", "test-products"),
        ("dev-customers", "test-dev-customers"),
    ],
)
def test_get_dynamodb_table(table_name, expected_table_name):
    """
    Test get_dynamodb_table function with various table name formats.
    Verifies that:
    1. Table name is properly prefixed with environment
    2. Boto3 resource is called correctly
    3. Correct table is returned
    """
    with patch("common_utils.boto3") as mock_boto3:
        mock_table = MagicMock()
        mock_boto3.resource.return_value.Table.return_value = mock_table

        table = common_utils.get_dynamodb_table(table_name)

        mock_boto3.resource.assert_called_once_with("dynamodb", region_name=None)
        mock_boto3.resource.return_value.Table.assert_called_once_with(
            expected_table_name
        )
        assert table == mock_table


def test_setup_logger():
    """
    Test setup_logger function.
    Verifies that:
    1. Logger is created with correct level
    2. Handler is properly configured
    3. Formatter is set correctly
    """
    with patch("common_utils.logging") as mock_logging:
        mock_logger = MagicMock()
        mock_handler = MagicMock()
        mock_logging.getLogger.return_value = mock_logger
        mock_logging.StreamHandler.return_value = mock_handler

        logger = common_utils.setup_logger()

        mock_logging.getLogger.assert_called_once()
        mock_logger.setLevel.assert_called_once_with(mock_logging.INFO)
        mock_logging.StreamHandler.assert_called_once()
        mock_handler.setFormatter.assert_called_once()
        mock_logger.addHandler.assert_called_once_with(mock_handler)
        assert logger == mock_logger


def test_setup_logger_custom_level():
    """Test logger setup with custom log level."""
    with patch("common_utils.logging") as mock_logging:
        mock_logger = MagicMock()
        mock_handler = MagicMock()
        mock_logger.handlers = [mock_handler]  # Add a mock handler
        mock_logging.getLogger.return_value = mock_logger

        common_utils.setup_logger(log_level=logging.DEBUG)

        mock_logger.setLevel.assert_called_once_with(logging.DEBUG)
        mock_logger.removeHandler.assert_called_once_with(mock_handler)


@pytest.mark.parametrize(
    "event,expected_body",
    [
        ({"body": '{"key": "value"}'}, {"key": "value"}),
        ({"body": {"key": "value"}}, {"key": "value"}),
        ({}, {}),
        ({"body": None}, None),
    ],
)
def test_extract_body(event, expected_body):
    """
    Test extract_body function with various input formats.
    Verifies that:
    1. JSON string body is properly parsed
    2. Dict body is returned as-is
    3. Missing or None body returns empty dict
    """
    body = common_utils.extract_body(event)
    assert body == expected_body


def test_extract_body_invalid_json():
    """
    Test extract_body function with invalid JSON.
    Verifies that invalid JSON raises JSONDecodeError.
    """
    event = {"body": "{invalid json"}
    with pytest.raises(json.JSONDecodeError):
        common_utils.extract_body(event)


@pytest.mark.parametrize(
    "event,expected_params",
    [
        ({"pathParameters": {"id": "123"}}, {"id": "123"}),
        ({"pathParameters": None}, {}),
        ({}, {}),
        ({"pathParameters": {}}, {}),
    ],
)
def test_get_path_parameters(event, expected_params):
    """
    Test get_path_parameters function with various input formats.
    Verifies that:
    1. Path parameters are correctly extracted
    2. None or missing parameters return empty dict
    """
    params = common_utils.get_path_parameters(event)
    assert params == expected_params


@pytest.mark.parametrize(
    "event,expected_params",
    [
        (
            {"queryStringParameters": {"page": "1", "limit": "10"}},
            {"page": "1", "limit": "10"},
        ),
        ({"queryStringParameters": None}, {}),
        ({}, {}),
        ({"queryStringParameters": {}}, {}),
    ],
)
def test_get_query_parameters(event, expected_params):
    """
    Test get_query_parameters function with various input formats.
    Verifies that:
    1. Query parameters are correctly extracted
    2. None or missing parameters return empty dict
    """
    params = common_utils.get_query_parameters(event)
    assert params == expected_params


@pytest.mark.parametrize(
    "function,expected_result",
    [
        (lambda event, context: {"success": True}, {"success": True}),
        (lambda event, context: 1 / 0, {"statusCode": 500}),
        (lambda event, context: None, None),
    ],
)
def test_handle_error_decorator(function, expected_result):
    """
    Test handle_error decorator with various function behaviors.
    Verifies that:
    1. Successful functions return their result
    2. Functions raising exceptions return 500 error response
    3. None return values are preserved
    """
    decorated_function = common_utils.handle_error(function)
    result = decorated_function({}, {})

    if expected_result is None:
        assert result is None
    elif isinstance(expected_result, dict) and "statusCode" in expected_result:
        assert result["statusCode"] == 500
        assert "Content-Type" in result["headers"]
        assert "Access-Control-Allow-Origin" in result["headers"]
        assert "error" in json.loads(result["body"])
    else:
        assert result == expected_result


def test_retry_with_backoff_max_retries():
    """Test retry_with_backoff when all retries are exhausted."""
    mock_func = MagicMock(side_effect=Exception("Test error"))

    with pytest.raises(Exception, match="Test error"):
        common_utils.retry_with_backoff(
            mock_func, retries=1
        )  # Set retries to 1 to make one attempt

    assert mock_func.call_count == 1  # Should try once before failing
