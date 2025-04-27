#!/bin/bash
set -e

# Default environment if not specified
ENV=${1:-dev}
SERVICE=${2:-all}
MOCK_API=${3:-1}  # Default to 1 (enable API mocking)

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Virtual environment not found. Creating one..."
    python -m venv venv
    if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
        . venv/bin/activate
    elif [ "$(expr substr $(uname -s) 1 5)" == "MINGW" ] || [ "$(expr substr $(uname -s) 1 4)" == "MSYS" ]; then
        . venv/Scripts/activate
    else
        echo "Unsupported operating system. Please activate the virtual environment manually."
        exit 1
    fi
    pip install --upgrade pip
    pip install -r requirements-dev.txt
else
    if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
        . venv/bin/activate
    elif [ "$(expr substr $(uname -s) 1 5)" == "MINGW" ] || [ "$(expr substr $(uname -s) 1 4)" == "MSYS" ]; then
        . venv/Scripts/activate
    else
        echo "Unsupported operating system. Please activate the virtual environment manually."
        exit 1
    fi
fi

# Create directory for test reports
mkdir -p coverage_reports

# Ensure responses library is installed
if ! pip list | grep -q "responses"; then
    echo "Installing responses library for API mocking..."
    pip install responses
fi

# Set PYTHONPATH to include lambda/shared_layer and current directory
SHARED_LAYER_PYTHON_PATH="$(pwd)/lambda/shared_layer/python"
SHARED_LAYER_PATH="$(pwd)/lambda/shared_layer"
export PYTHONPATH="$SHARED_LAYER_PYTHON_PATH:$SHARED_LAYER_PATH:$(pwd):$PYTHONPATH"

# Set API mocking flag
export MOCK_API="$MOCK_API"
echo "API mocking: $([ "$MOCK_API" = "1" ] && echo "enabled" || echo "disabled")"

# Print debug info
echo "PYTHONPATH: $PYTHONPATH"

echo "Running tests with mocked AWS services ($SERVICE) for environment: $ENV"
python scripts/mock_aws_services.py --service $SERVICE --env $ENV

# Handle additional arguments (test path)
if [ "$#" -gt 3 ]; then
    # Pass remaining arguments to the script
    python scripts/mock_aws_services.py --service $SERVICE --env $ENV --test-path "${@:4}"
fi

echo "Mock tests completed!"
echo "Test report available at: coverage_reports/mock_integration_junit.xml" 