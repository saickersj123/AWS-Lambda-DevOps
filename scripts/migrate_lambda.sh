#!/bin/bash
# Script to migrate Lambda functions from the old structure to the new DevOps structure

set -e

# Set default values
SOURCE_DIR="lambda-old"
TARGET_DIR="lambda"
FUNCTION_NAME=""
ENVIRONMENT="dev"

# Parse command line arguments
function usage {
    echo "Usage: $0 -f FUNCTION_NAME [-s SOURCE_DIR] [-t TARGET_DIR] [-e ENVIRONMENT]"
    echo "  -f FUNCTION_NAME    Name of the function to migrate (required)"
    echo "  -s SOURCE_DIR       Source directory containing old Lambda functions (default: lambda-old)"
    echo "  -t TARGET_DIR       Target directory for the new structure (default: lambda)"
    echo "  -e ENVIRONMENT      Environment to deploy to (dev, staging, prod) (default: dev)"
    echo "  -h                  Display this help message"
    exit 1
}

while getopts ":f:s:t:e:h" opt; do
    case $opt in
        f) FUNCTION_NAME=$OPTARG ;;
        s) SOURCE_DIR=$OPTARG ;;
        t) TARGET_DIR=$OPTARG ;;
        e) ENVIRONMENT=$OPTARG ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done

# Check if function name is provided
if [ -z "$FUNCTION_NAME" ]; then
    echo "Error: Function name is required."
    usage
fi

# Check if source directory exists
if [ ! -d "$SOURCE_DIR/$FUNCTION_NAME" ]; then
    echo "Error: Function $FUNCTION_NAME not found in $SOURCE_DIR."
    exit 1
fi

# Create function category based on function name
determine_category() {
    local func_name=$1
    
    if [[ $func_name == c8_* || $func_name == *kiosk* ]]; then
        echo "kiosk"
    elif [[ $func_name == *device* || $func_name == *screen* ]]; then
        echo "device"
    elif [[ $func_name == *payment* || $func_name == *stripe* || $func_name == *charge* ]]; then
        echo "payment"
    elif [[ $func_name == *usage* || $func_name == *Transaction* ]]; then
        echo "analytics"
    elif [[ $func_name == *maintenance* || $func_name == *reboot* || $func_name == *status* ]]; then
        echo "maintenance"
    else
        echo "misc"
    fi
}

CATEGORY=$(determine_category "$FUNCTION_NAME")
TARGET_FUNCTION_DIR="$TARGET_DIR/$CATEGORY/$FUNCTION_NAME"

echo "Migrating function $FUNCTION_NAME to $TARGET_FUNCTION_DIR..."

# Create target directory
mkdir -p "$TARGET_FUNCTION_DIR"

# Copy function code
cp -r "$SOURCE_DIR/$FUNCTION_NAME/"* "$TARGET_FUNCTION_DIR/"

# Refactor function to use shared utilities if they exist
if [ -f "$TARGET_DIR/shared_layer/common_utils.py" ]; then
    echo "Refactoring function to use shared utilities..."
    
    # Find main Lambda handler file
    HANDLER_FILE=$(find "$TARGET_FUNCTION_DIR" -name "*.py" -type f -exec grep -l "lambda_handler" {} \;)
    
    if [ -n "$HANDLER_FILE" ]; then
        # Add import for common utilities
        sed -i '1i\from common_utils import setup_logger, get_dynamodb_table, format_response, handle_error' "$HANDLER_FILE"
        
        # Replace direct boto3 imports with shared utilities
        sed -i 's/import boto3/# import boto3 -- using common_utils/g' "$HANDLER_FILE"
        sed -i 's/dynamodb = boto3.resource("dynamodb")/# dynamodb = boto3.resource("dynamodb") -- using common_utils/g' "$HANDLER_FILE"
        sed -i 's/table = dynamodb.Table(/table = get_dynamodb_table(/g' "$HANDLER_FILE"
        
        # Replace logger setup
        sed -i 's/logger = logging.getLogger()/logger = setup_logger()/g' "$HANDLER_FILE"
        
        # Add error handling decorator to lambda_handler function
        sed -i 's/def lambda_handler(event, context)/@handle_error\ndef lambda_handler(event, context)/g' "$HANDLER_FILE"
        
        echo "Refactoring completed for $HANDLER_FILE"
    else
        echo "Warning: Could not find Lambda handler in $FUNCTION_NAME."
    fi
fi

# Create or update requirements.txt
if [ ! -f "$TARGET_FUNCTION_DIR/requirements.txt" ]; then
    cat > "$TARGET_FUNCTION_DIR/requirements.txt" << EOF
# No additional dependencies required.
# All common dependencies are provided by the shared layer:
# - boto3
# - requests
# - python-dateutil
EOF
fi

# Create a basic README file
cat > "$TARGET_FUNCTION_DIR/README.md" << EOF
# $FUNCTION_NAME

## Description
This Lambda function was migrated from the legacy project structure.

## Features
- TODO: Document the functionality

## Dependencies
All common dependencies are provided by the shared layer. See requirements.txt for function-specific dependencies.

## Environment Variables
TODO: Document required environment variables.

## API Gateway Integration
TODO: Document the API Gateway endpoints that use this function.
EOF

echo "Creating Terraform configuration for $FUNCTION_NAME in $ENVIRONMENT environment..."

# Determine API Gateway path and method
API_PATH=$(echo "$FUNCTION_NAME" | tr '_' '-')
API_METHOD="GET"

# If the function name contains "update" or "create", use POST method
if [[ "$FUNCTION_NAME" == *update* || "$FUNCTION_NAME" == *create* || "$FUNCTION_NAME" == *payment* ]]; then
    API_METHOD="POST"
fi

# Create function configuration in the environment variables.tf file
FUNCTIONS_VAR_FILE="terraform/environments/$ENVIRONMENT/variables.tf"

if [ -f "$FUNCTIONS_VAR_FILE" ]; then
    # Check if the function is already in the variables.tf file
    if ! grep -q "name = \"$FUNCTION_NAME\"" "$FUNCTIONS_VAR_FILE"; then
        # Find the lambda_functions variable block
        LINE_NUM=$(grep -n "variable \"lambda_functions\"" "$FUNCTIONS_VAR_FILE" | cut -d: -f1)
        
        if [ -n "$LINE_NUM" ]; then
            # Find the end of the default block
            END_LINE=$(tail -n +$LINE_NUM "$FUNCTIONS_VAR_FILE" | grep -n "]$" | head -1 | cut -d: -f1)
            END_LINE=$((LINE_NUM + END_LINE - 1))
            
            # Insert the new function before the closing bracket
            sed -i "${END_LINE}i\\    {\\n      name                 = \"$FUNCTION_NAME\"\\n      description          = \"$(echo $FUNCTION_NAME | tr '-_' ' ' | sed 's/\b\(.\)/\u\1/g')\"\\n      handler              = \"index.lambda_handler\"\\n      runtime              = \"python3.11\"\\n      timeout              = 30\\n      memory_size          = 128\\n      path_part            = \"$API_PATH\"\\n      http_method          = \"$API_METHOD\"\\n      environment_variables = {}\\n      additional_policies  = []\\n    }," "$FUNCTIONS_VAR_FILE"
            
            echo "Added $FUNCTION_NAME to Terraform configuration."
        else
            echo "Warning: Could not find lambda_functions variable in $FUNCTIONS_VAR_FILE."
        fi
    else
        echo "Function $FUNCTION_NAME already exists in Terraform configuration."
    fi
else
    echo "Warning: Terraform environment file $FUNCTIONS_VAR_FILE not found."
fi

echo "Migration of $FUNCTION_NAME completed successfully!" 