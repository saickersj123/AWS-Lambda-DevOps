import json
import os
import re

import boto3
import pytest
import requests
import responses


def pytest_addoption(parser):
    """Add command-line options to pytest."""
    parser.addoption(
        "--env",
        default="dev",
        help="Environment to run tests against (dev, staging, prod)",
    )
    parser.addoption(
        "--mock-api",
        action="store_true",
        default=False,
        help="Mock API calls (default: False)",
    )


@pytest.fixture(scope="session")
def environment(request):
    """Get the environment from the command line option."""
    return request.config.getoption("--env")


@pytest.fixture(scope="session")
def api_url(environment, aws_credentials):
    """Get the base API URL for the specified environment."""
    # First check if we have an environment variable override
    env_var_url = os.environ.get(f"API_URL_{environment.upper()}")
    if env_var_url:
        print(f"Using API URL from environment variable: {env_var_url}")
        return env_var_url

    # Fallback URLs if API Gateway lookup fails
    fallback_urls = {
        "dev": "https://api-dev.example.com",
        "staging": "https://api-staging.example.com",
        "prod": "https://api.example.com",
    }

    try:
        # First, try HTTP API (API Gateway v2)
        apigwv2_client = boto3.client(
            "apigatewayv2",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )

        # List all HTTP APIs
        try:
            http_apis = apigwv2_client.get_apis()

            # Find HTTP API for current environment
            http_api_id = None
            for api in http_apis.get("Items", []):
                if environment in api.get("Name", "").lower():
                    http_api_id = api.get("ApiId")
                    break

            if http_api_id:
                # Get stages for the HTTP API
                http_stages = apigwv2_client.get_stages(ApiId=http_api_id)
                http_stage_name = None

                # Find the stage matching our environment
                for stage in http_stages.get("Items", []):
                    if environment in stage.get("StageName", "").lower():
                        http_stage_name = stage.get("StageName")
                        break

                if not http_stage_name:
                    # If no matching stage, try default
                    for stage in http_stages.get("Items", []):
                        if stage.get("StageName") == "default":
                            http_stage_name = "default"
                            break

                if not http_stage_name and http_stages.get("Items"):
                    # Just use the first stage
                    http_stage_name = http_stages.get("Items")[0].get("StageName")

                if http_stage_name:
                    # Construct HTTP API URL
                    api_url = f"https://{http_api_id}.execute-api.{aws_credentials['region_name']}.amazonaws.com/{http_stage_name}"
                    print(f"Using HTTP API URL from AWS API Gateway v2: {api_url}")
                    return api_url
        except Exception as e:
            print(f"Error checking HTTP APIs: {str(e)}")

        # Fall back to REST API (API Gateway v1) lookup
        client = boto3.client(
            "apigateway",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )

        # List all REST APIs
        apis = client.get_rest_apis()

        # Find the API for the current environment (assumes API name contains environment)
        api_id = None
        for api in apis.get("items", []):
            if environment in api.get("name", "").lower():
                api_id = api.get("id")
                break

        if not api_id:
            print(
                f"Warning: No API found for environment '{environment}', using fallback URL"
            )
            return fallback_urls.get(environment)

        # Get the current stage for this environment
        stages = client.get_stages(restApiId=api_id)
        stage_name = None

        # Find the stage matching our environment
        for stage in stages.get("item", []):
            if environment in stage.get("stageName", "").lower():
                stage_name = stage.get("stageName")
                break

        if not stage_name:
            # If no matching stage, use the first one
            stage_name = stages.get("item", [{}])[0].get("stageName")

        if not stage_name:
            print(f"Warning: No stage found for API '{api_id}', using fallback URL")
            return fallback_urls.get(environment)

        # Construct the API URL
        api_url = f"https://{api_id}.execute-api.{aws_credentials['region_name']}.amazonaws.com/{stage_name}"  # noqa: E231
        print(f"Using REST API URL from AWS API Gateway: {api_url}")
        return api_url

    except Exception as e:
        print(f"Error retrieving API URL from AWS API Gateway: {str(e)}")
        print(f"Using fallback URL for {environment}")
        return fallback_urls.get(environment)


@pytest.fixture(scope="session")
def aws_credentials():
    """Get AWS credentials from environment variables or shared credentials."""
    return {
        "aws_access_key_id": os.environ.get("AWS_ACCESS_KEY_ID"),
        "aws_secret_access_key": os.environ.get("AWS_SECRET_ACCESS_KEY"),
        "aws_session_token": os.environ.get("AWS_SESSION_TOKEN"),
        "region_name": os.environ.get("AWS_DEFAULT_REGION", "us-east-2"),
    }


@pytest.fixture(scope="session")
def use_moto():
    """Determine if we should use moto for AWS service mocking.

    This checks for environment variables indicating mock settings and returns
    a dictionary with services that should be mocked.
    """
    # Default to not mocking
    mock_settings = {
        "dynamodb": False,
        "s3": False,
        "sqs": False,
        "lambda": False,
    }

    # Check environment variables for each service
    if os.environ.get("MOCK_DYNAMODB", "0") == "1":
        mock_settings["dynamodb"] = True
        print("DynamoDB mocking enabled")

    if os.environ.get("MOCK_S3", "0") == "1":
        mock_settings["s3"] = True
        print("S3 mocking enabled")

    if os.environ.get("MOCK_SQS", "0") == "1":
        mock_settings["sqs"] = True
        print("SQS mocking enabled")

    if os.environ.get("MOCK_LAMBDA", "0") == "1":
        mock_settings["lambda"] = True
        print("Lambda mocking enabled")

    # If we're in Jenkins fallback mode, override everything to mocked
    if os.environ.get("JENKINS_MOCK_FALLBACK", "0") == "1":
        for service in mock_settings:
            mock_settings[service] = True
        print("Jenkins mock fallback enabled - all AWS services will be mocked")

    return mock_settings


@pytest.fixture(scope="session")
def dynamodb_resource(aws_credentials, use_moto):
    """Create a DynamoDB resource client."""
    if use_moto["dynamodb"]:
        import moto

        with moto.mock_dynamodb():
            dynamodb = boto3.resource(
                "dynamodb",
                region_name=aws_credentials["region_name"],
                aws_access_key_id=aws_credentials["aws_access_key_id"],
                aws_secret_access_key=aws_credentials["aws_secret_access_key"],
                aws_session_token=aws_credentials.get("aws_session_token"),
            )

            # Create test tables
            # devices table
            dynamodb.create_table(
                TableName="devices",
                KeySchema=[{"AttributeName": "device_id", "KeyType": "HASH"}],
                AttributeDefinitions=[
                    {"AttributeName": "device_id", "AttributeType": "S"}
                ],
                BillingMode="PAY_PER_REQUEST",
            )

            print("Created mocked DynamoDB tables")
            yield dynamodb
    else:
        # Use real DynamoDB
        dynamodb = boto3.resource(
            "dynamodb",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )
        yield dynamodb


@pytest.fixture(scope="session")
def s3_resource(aws_credentials, use_moto):
    """Create an S3 resource client."""
    if use_moto["s3"]:
        import moto

        with moto.mock_s3():
            s3 = boto3.resource(
                "s3",
                region_name=aws_credentials["region_name"],
                aws_access_key_id=aws_credentials["aws_access_key_id"],
                aws_secret_access_key=aws_credentials["aws_secret_access_key"],
                aws_session_token=aws_credentials.get("aws_session_token"),
            )

            # Create test buckets
            # logs bucket
            s3.create_bucket(
                Bucket="test-logs",
                CreateBucketConfiguration={
                    "LocationConstraint": aws_credentials["region_name"]
                },
            )

            print("Created mocked S3 buckets")
            yield s3
    else:
        # Use real S3
        s3 = boto3.resource(
            "s3",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )
        yield s3


@pytest.fixture(scope="session")
def sqs_resource(aws_credentials, use_moto):
    """Create an SQS resource client."""
    if use_moto["sqs"]:
        import moto

        with moto.mock_sqs():
            sqs = boto3.resource(
                "sqs",
                region_name=aws_credentials["region_name"],
                aws_access_key_id=aws_credentials["aws_access_key_id"],
                aws_secret_access_key=aws_credentials["aws_secret_access_key"],
                aws_session_token=aws_credentials.get("aws_session_token"),
            )

            # Create test queues
            sqs.create_queue(QueueName="test-queue")

            print("Created mocked SQS queues")
            yield sqs
    else:
        # Use real SQS
        sqs = boto3.resource(
            "sqs",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )
        yield sqs


@pytest.fixture(scope="session")
def lambda_client(aws_credentials, use_moto):
    """Create a Lambda client."""
    if use_moto["lambda"]:
        import moto

        with moto.mock_lambda():
            lambda_client = boto3.client(
                "lambda",
                region_name=aws_credentials["region_name"],
                aws_access_key_id=aws_credentials["aws_access_key_id"],
                aws_secret_access_key=aws_credentials["aws_secret_access_key"],
                aws_session_token=aws_credentials.get("aws_session_token"),
            )

            print("Mocking Lambda client")
            yield lambda_client
    else:
        # Use real Lambda client
        lambda_client = boto3.client(
            "lambda",
            region_name=aws_credentials["region_name"],
            aws_access_key_id=aws_credentials["aws_access_key_id"],
            aws_secret_access_key=aws_credentials["aws_secret_access_key"],
            aws_session_token=aws_credentials.get("aws_session_token"),
        )
        yield lambda_client


@pytest.fixture(scope="session")
def api_key(environment):
    """Get API key for the specified environment."""
    # Ideally, this would be retrieved from AWS Secrets Manager or similar
    return os.environ.get(f"API_KEY_{environment.upper()}", "test-api-key")


@pytest.fixture(scope="session")
def api_headers(api_key):
    """Get headers for API requests."""
    return {"Content-Type": "application/json", "x-api-key": api_key}


@pytest.fixture(scope="function")
def test_device_id():
    """Generate a unique test device ID."""
    import uuid

    return f"test-device-{uuid.uuid4()}"


@pytest.fixture(scope="function")
def create_test_device(api_url, api_headers, test_device_id, mock_api):
    """Create a test device for testing.

    This fixture creates a test device via API call. If API mocking is enabled,
    it will use the mocked response. If real API calls are enabled, it will
    create a real device through the API.

    In case of connection errors, it will fall back to a dummy device for tests
    to continue.
    """
    device_data = {
        "device_id": test_device_id,
        "status": "test",
        "battery_level": 100,
        "firmware_version": "test-1.0.0",
    }

    # If API is mocked, the mock_api fixture will handle the response
    # If not, we'll try to create a real device
    if os.environ.get("MOCK_API", "0") != "1" and not os.environ.get("CI", "0") == "1":
        try:
            url = f"{api_url}/device-status"
            print(f"Attempting to create test device at: {url}")

            # Test connectivity first
            try:
                # Send a HEAD request first to check connectivity
                requests.head(api_url, timeout=3)
                print(f"API endpoint is reachable: {api_url}")
            except requests.exceptions.RequestException as e:
                print(f"API endpoint connectivity test failed: {e}")
                print("Will attempt to create device anyway...")

            # Now try to create the test device
            response = requests.post(
                url,
                json=device_data,
                headers=api_headers,
                timeout=10,  # Add a reasonable timeout
            )

            if response.status_code == 200:
                print(f"Successfully created test device: {test_device_id}")
                # Update device_data with actual response if needed
                try:
                    resp_data = response.json()
                    if isinstance(resp_data, dict) and "body" in resp_data:
                        # Handle API Gateway format if needed
                        body_data = resp_data["body"]
                        if isinstance(body_data, str):
                            body_data = json.loads(body_data)
                        device_data.update(body_data)
                    elif isinstance(resp_data, dict):
                        device_data.update(resp_data)
                except (json.JSONDecodeError, ValueError) as e:
                    print(f"Warning: Could not parse response JSON: {e}")
            else:
                print(
                    f"Warning: Failed to create test device: {response.status_code} {response.text}"
                )
                # Continue with the test data even if creation fails
        except requests.exceptions.ConnectionError as e:
            # If connection fails, log the error and continue with the test data
            print(f"Warning: Connection error when creating test device: {e}")
            print("Continuing with test data without actual API call")
        except requests.exceptions.Timeout as e:
            print(f"Warning: Timeout error when creating test device: {e}")
            print("Continuing with test data without actual API call")
        except Exception as e:
            # Log any other exceptions but don't fail the test
            print(f"Warning: Unexpected error creating test device: {e}")
            print("Continuing with test data without actual API call")
    else:
        print(f"Using mocked device data for {test_device_id} (API mocking is enabled)")

    yield device_data

    # Cleanup: No need to delete as we're using unique IDs
    # If this were a persistent test that needed cleanup, we would delete here


@pytest.fixture(scope="function")
def mock_api(request, api_url):
    """Mock API responses for integration tests.

    This fixture will mock API responses if:
    1. MOCK_API environment variable is set to "1" (explicit mocking)
    2. pytest is run with --mock-api flag
    3. We're running in CI and ENABLE_REAL_API_CALLS is not set to "1"
    """
    # Check if we should mock API calls
    should_mock = (
        os.environ.get("MOCK_API", "0") == "1"
        # Check if we're in a CI environment and real API calls aren't explicitly enabled
        or (
            os.environ.get("CI", "0") == "1"
            and os.environ.get("ENABLE_REAL_API_CALLS", "0") != "1"
        )
        # Check if --mock-api flag was passed to pytest
        or request.config.getoption("--mock-api", default=False)
    )

    # Add some debug output
    print(f"API mocking {'enabled' if should_mock else 'disabled'}")
    print(f"API URL: {api_url}")

    if should_mock:
        with responses.RequestsMock(assert_all_requests_are_fired=False) as rsps:
            # Use the dynamically obtained API URL instead of hardcoding
            base_url = api_url

            # GET device status - base endpoint
            rsps.add(
                responses.GET,
                f"{base_url}/device-status",
                json={
                    "device_id": "test-device-123",
                    "status": "online",
                    "battery_level": 100,
                },
                status=200,
            )

            # GET device status with ID - using regex to match any device ID
            rsps.add_callback(
                responses.GET,
                re.compile(f"{base_url}/device-status/.*"),
                callback=lambda request: (
                    200,
                    {"Content-Type": "application/json"},
                    json.dumps(
                        {
                            "statusCode": 200,
                            "body": {
                                "device_id": request.path_url.split("/")[-1],
                                "status": "online",
                                "battery_level": 100,
                                "firmware_version": "1.0.0",
                            },
                        }
                    ),
                ),
            )

            # POST device status
            rsps.add(
                responses.POST,
                f"{base_url}/device-status",
                json={
                    "statusCode": 200,
                    "body": {"success": True, "message": "Device status updated"},
                },
                status=200,
            )

            # POST batch update
            rsps.add(
                responses.POST,
                f"{base_url}/device-status/batch",
                json={
                    "statusCode": 200,
                    "body": {"success": True, "message": "Batch update successful"},
                },
                status=200,
            )

            # PUT device status
            rsps.add(
                responses.PUT,
                f"{base_url}/device-status",
                json={
                    "statusCode": 200,
                    "body": {"success": True, "message": "Device status updated"},
                },
                status=200,
            )

            # DELETE device status
            rsps.add(
                responses.DELETE,
                f"{base_url}/device-status",
                json={
                    "statusCode": 200,
                    "body": {"success": True, "message": "Device status deleted"},
                },
                status=200,
            )

            yield rsps
    else:
        # No mocking, use real API
        yield None


@pytest.fixture(scope="session", autouse=True)
def debug_api_environment(api_url, environment):
    """Debug the API environment configuration and print URLs for verification."""
    print("\n====== API ENVIRONMENT DEBUG ======")
    print(f"Environment: {environment}")
    print(f"Base API URL: {api_url}")
    print(f"Device Status endpoint: {api_url}/device-status")

    # Try accessing the API to verify it's reachable
    try:
        response = requests.get(f"{api_url}", timeout=5)
        print(f"Base API Status: {response.status_code}")
    except Exception as e:
        print(f"Error connecting to API: {str(e)}")

    # Try accessing specific endpoint (no auth required for this check)
    try:
        response = requests.get(f"{api_url}/device-status", timeout=5)
        print(f"Device Status endpoint status: {response.status_code}")
        if response.status_code != 200:
            print(f"Response body: {response.text[:500]}")
    except Exception as e:
        print(f"Error connecting to device-status: {str(e)}")

    print("====================================\n")
    return api_url
