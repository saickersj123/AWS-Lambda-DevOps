from common_utils import (
    extract_body,
    format_response,
    get_dynamodb_table,
    get_path_parameters,
    handle_error,
    setup_logger,
)

# Define version number
VERSION = "1.2.0"

# Initialize logger
logger = setup_logger()

# Get DynamoDB table
device_table = get_dynamodb_table("devices")

# Added this comment to test if Terraform detects code changes


@handle_error
def lambda_handler(event, context):
    """
    Handles updates to device status.

    This function processes incoming device status updates and stores them in DynamoDB.
    It supports both POST (update) and GET (retrieve) operations.
    """
    logger.info(f"Received event: {event}")

    # Extract HTTP method
    http_method = event.get("httpMethod", "GET")

    if http_method == "POST":
        # Handle device status update
        return update_device_status(event)
    else:
        # Handle device status retrieval
        return get_device_status(event)


def update_device_status(event):
    """Update device status in DynamoDB."""
    # Extract request body
    body = extract_body(event)

    # Validate required fields
    required_fields = ["device_id", "status"]
    for field in required_fields:
        if field not in body:
            return format_response(400, {"error": f"Missing required field: {field}"})

    # Extract device info
    device_id = body["device_id"]
    status = body["status"]
    timestamp = body.get("timestamp", str(get_current_timestamp()))

    # Additional device info (optional)
    battery_level = body.get("battery_level")
    connection_strength = body.get("connection_strength")
    firmware_version = body.get("firmware_version")

    # Prepare update item
    update_item = {"device_id": device_id, "status": status, "last_updated": timestamp}

    # Add optional fields if present
    if battery_level is not None:
        update_item["battery_level"] = battery_level
    if connection_strength is not None:
        update_item["connection_strength"] = connection_strength
    if firmware_version is not None:
        update_item["firmware_version"] = firmware_version

    # Update DynamoDB
    logger.info(f"Updating device status for device_id: {device_id}")
    device_table.put_item(Item=update_item)

    return format_response(
        200,
        {
            "message": "Device status updated successfully",
            "device_id": device_id,
            "status": status,
        },
    )


def get_device_status(event):
    """Retrieve device status from DynamoDB."""
    # Extract path parameters
    path_params = get_path_parameters(event)
    device_id = path_params.get("device_id")

    if not device_id:
        return format_response(400, {"error": "Missing device_id parameter"})

    # Query DynamoDB
    logger.info(f"Retrieving status for device_id: {device_id}")
    response = device_table.get_item(Key={"device_id": device_id})

    # Check if item exists
    if "Item" not in response:
        return format_response(404, {"error": f"Device not found: {device_id}"})

    # Return device status
    return format_response(200, response["Item"])


def get_current_timestamp():
    """Get current timestamp in ISO format."""
    from datetime import UTC, datetime

    return datetime.now(UTC).isoformat()


def validate_device_id(device_id):
    """Validate that the device ID is in the correct format."""
    if not device_id or not isinstance(device_id, str):
        return False

    # Check if device ID follows the expected pattern
    # For example: 'dev-' followed by alphanumeric characters
    if not device_id.startswith("dev-"):
        return False

    return len(device_id) >= 6  # Minimum length check
