from unittest.mock import MagicMock, patch

import pytest

from lambda_functions.shared_layer.python.common_utils import (
    get_dynamodb_client,
    get_dynamodb_resource,
    get_iot_client,
    get_iot_data_client,
    get_s3_client,
    get_ssm_client,
    get_ssm_parameter,
    get_user_id_from_event,
    retry_with_backoff,
)


@pytest.mark.parametrize(
    "client_func,service_name",
    [
        (get_dynamodb_resource, "dynamodb"),
        (get_dynamodb_client, "dynamodb"),
        (get_iot_client, "iot"),
        (get_iot_data_client, "iot-data"),
        (get_s3_client, "s3"),
        (get_ssm_client, "ssm"),
    ],
)
def test_aws_clients(client_func, service_name):
    """Test AWS client initialization with and without region."""
    # Test without region
    with patch(
        "boto3.resource" if client_func == get_dynamodb_resource else "boto3.client"
    ) as mock_client:
        client_func()
        mock_client.assert_called_once_with(service_name, region_name=None)

    # Test with region
    with patch(
        "boto3.resource" if client_func == get_dynamodb_resource else "boto3.client"
    ) as mock_client:
        client_func(region="us-west-2")
        mock_client.assert_called_once_with(service_name, region_name="us-west-2")


def test_get_ssm_parameter():
    """Test SSM parameter retrieval."""
    with patch(
        "lambda_functions.shared_layer.python.common_utils.get_ssm_client"
    ) as mock_client:
        mock_response = {"Parameter": {"Value": "test-value"}}
        mock_client.return_value.get_parameter.return_value = mock_response

        value = get_ssm_parameter("test-param")
        assert value == "test-value"
        mock_client.return_value.get_parameter.assert_called_once_with(
            Name="test-param", WithDecryption=True
        )


def test_retry_with_backoff_success():
    """Test retry with backoff when function succeeds on first try."""
    mock_func = MagicMock(return_value="success")
    result = retry_with_backoff(mock_func)
    assert result == "success"
    mock_func.assert_called_once()


def test_retry_with_backoff_failure():
    """Test retry with backoff when function fails all attempts."""
    mock_func = MagicMock(side_effect=Exception("Test error"))
    with pytest.raises(Exception, match="Test error"):
        retry_with_backoff(mock_func, retries=2)
    assert mock_func.call_count == 2


def test_get_user_id_from_event():
    """Test user ID extraction from API Gateway event."""
    # Test with Cognito username
    event = {
        "requestContext": {"authorizer": {"claims": {"cognito:username": "test-user"}}}
    }
    assert get_user_id_from_event(event) == "test-user"

    # Test with sub claim
    event = {"requestContext": {"authorizer": {"claims": {"sub": "test-sub"}}}}
    assert get_user_id_from_event(event) == "test-sub"

    # Test with no authorizer
    event = {}
    assert get_user_id_from_event(event) is None

    # Test with no claims
    event = {"requestContext": {"authorizer": {}}}
    assert get_user_id_from_event(event) is None
