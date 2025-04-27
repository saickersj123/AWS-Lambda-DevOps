import json
import logging
import os
import secrets
import time
from functools import wraps

import boto3

# Environment-specific settings
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")


# Standard AWS service clients
def get_dynamodb_resource(region=None):
    """Return a boto3 DynamoDB resource with the specified region."""
    return boto3.resource("dynamodb", region_name=region)


def get_dynamodb_client(region=None):
    """Return a boto3 DynamoDB client with the specified region."""
    return boto3.client("dynamodb", region_name=region)


def get_dynamodb_table(table_name, region=None, env_prefix=None):
    """Get a DynamoDB table resource with environment-specific naming."""
    dynamodb = get_dynamodb_resource(region)

    # Use provided prefix or get from environment
    env = env_prefix or os.environ.get("ENVIRONMENT", "dev")

    # Check if the table name already has the environment prefix
    if table_name.startswith(f"{env}-"):
        prefixed_table_name = table_name
    else:
        prefixed_table_name = f"{env}-{table_name}"

    return dynamodb.Table(prefixed_table_name)


def get_iot_client(region=None):
    """Return a boto3 IoT client with the specified region."""
    return boto3.client("iot", region_name=region)


def get_iot_data_client(region=None):
    """Return a boto3 IoT Data client with the specified region."""
    return boto3.client("iot-data", region_name=region)


def get_s3_client(region=None):
    """Return a boto3 S3 client with the specified region."""
    return boto3.client("s3", region_name=region)


def get_ssm_client(region=None):
    """Return a boto3 SSM client with the specified region."""
    return boto3.client("ssm", region_name=region)


def get_ssm_parameter(param_name, with_decryption=True, region=None):
    """Get a parameter from SSM Parameter Store."""
    ssm = get_ssm_client(region)
    response = ssm.get_parameter(Name=param_name, WithDecryption=with_decryption)
    return response["Parameter"]["Value"]


# Logging setup
def setup_logger(log_level=None):
    """Configure and return a logger with JSON formatting."""
    logger = logging.getLogger()

    if log_level:
        logger.setLevel(log_level)
    else:
        logger.setLevel(logging.INFO)

    # Remove existing handlers to avoid duplicates
    for handler in logger.handlers:
        logger.removeHandler(handler)

    # Create handler with JSON formatting
    handler = logging.StreamHandler()
    formatter = logging.Formatter(
        '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s", "environment": "'
        + ENVIRONMENT
        + '"}'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    return logger


# Response formatting
def format_response(status_code, body, headers=None):
    """Format a standard API Gateway response."""
    if headers is None:
        headers = {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Credentials": True,
        }

    return {"statusCode": status_code, "headers": headers, "body": json.dumps(body)}


# Error handling decorator
def handle_error(func):
    """Decorator for handling errors in Lambda functions."""

    @wraps(func)
    def wrapper(event, context):
        logger = setup_logger()
        try:
            return func(event, context)
        except Exception as e:
            logger.exception(f"Error in {func.__name__}: {str(e)}")
            return format_response(500, {"error": str(e)})

    return wrapper


# Retry logic with exponential backoff
def retry_with_backoff(func, retries=3, backoff_in_seconds=1):
    """Retry a function with exponential backoff."""
    for i in range(retries):
        try:
            return func()
        except Exception as e:
            if i == retries - 1:  # Last attempt
                raise e

            # Calculate backoff with jitter using cryptographically secure random number
            backoff = backoff_in_seconds * (2**i) + secrets.randbelow(1000) / 1000
            time.sleep(backoff)

    # This should never happen, but just in case
    raise Exception("Retry with backoff failed after all retries")


# Helper functions for API Gateway events
def extract_body(event):
    """Extract and parse the body from an API Gateway event."""
    if "body" not in event:
        return {}

    body = event["body"]
    if isinstance(body, str):
        return json.loads(body)
    return body


def get_user_id_from_event(event):
    """Extract user ID from an API Gateway event with JWT authorizer."""
    if "requestContext" in event and "authorizer" in event["requestContext"]:
        claims = event["requestContext"]["authorizer"].get("claims", {})
        return claims.get("sub") or claims.get("cognito:username")
    return None


def get_path_parameters(event):
    """Extract path parameters from an API Gateway event."""
    return event.get("pathParameters", {}) or {}


def get_query_parameters(event):
    """Extract query string parameters from an API Gateway event."""
    return event.get("queryStringParameters", {}) or {}
