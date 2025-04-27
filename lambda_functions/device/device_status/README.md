# Device Status Lambda Function

## Description
This Lambda function handles device status updates and retrieval. It stores device status information in DynamoDB and provides endpoints for both updating and retrieving device statuses.

## Features
- Update device status (POST)
- Retrieve device status (GET)
- Store additional device information including battery level, connection strength, and firmware version

## Dependencies
All common dependencies are provided by the shared layer. See requirements.txt for function-specific dependencies.

## Environment Variables
- ENVIRONMENT - The deployment environment (dev, staging, prod)

## API Gateway Integration
This function is designed to be integrated with API Gateway with the following endpoints:

- **GET /device-status/{device_id}** - Retrieve status for a specific device
- **POST /device-status** - Update device status

### Example Request (POST)
```json
{
  "device_id": "device123",
  "status": "active",
  "battery_level": 85,
  "connection_strength": 4,
  "firmware_version": "1.2.3"
}
```

### Example Response (GET)
```json
{
  "device_id": "device123",
  "status": "active",
  "last_updated": "2023-03-05T14:30:45.123456",
  "battery_level": 85,
  "connection_strength": 4,
  "firmware_version": "1.2.3"
}
``` 