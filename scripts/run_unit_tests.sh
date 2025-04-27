#!/bin/bash
set -e

# Check if we're running in a CI environment with an activated venv
if [ -z "$VIRTUAL_ENV" ]; then
    # Not in an activated venv, need to set one up
    
    # Check if virtual environment exists using VENV_NAME or fallback to "venv"
    VENV_DIR=${VENV_NAME:-venv}
    if [ ! -d "$VENV_DIR" ]; then
        echo "Virtual environment not found. Creating one at $VENV_DIR..."
        python -m venv $VENV_DIR
        if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
            . $VENV_DIR/bin/activate
        elif [ "$(expr substr $(uname -s) 1 5)" == "MINGW" ] || [ "$(expr substr $(uname -s) 1 4)" == "MSYS" ]; then
            . $VENV_DIR/Scripts/activate
        else
            echo "Unsupported operating system. Please activate the virtual environment manually."
            exit 1
        fi
        pip install --upgrade pip
        pip install -r requirements-dev.txt
    else
        if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
            . $VENV_DIR/bin/activate
        elif [ "$(expr substr $(uname -s) 1 5)" == "MINGW" ] || [ "$(expr substr $(uname -s) 1 4)" == "MSYS" ]; then
            . $VENV_DIR/Scripts/activate
        else
            echo "Unsupported operating system. Please activate the virtual environment manually."
            exit 1
        fi
    fi
else
    echo "Using existing virtual environment: $VIRTUAL_ENV"
fi

# Create directory for coverage reports
mkdir -p coverage_reports

# Parse arguments
SPECIFIC_TEST=""
if [ "$#" -gt 0 ]; then
    SPECIFIC_TEST=$1
fi

# Set PYTHONPATH to include lambda/shared_layer and current directory
SHARED_LAYER_PYTHON_PATH="$(pwd)/lambda_functions/shared_layer/python"
SHARED_LAYER_PATH="$(pwd)/lambda_functions/shared_layer"
export PYTHONPATH="$SHARED_LAYER_PYTHON_PATH:$SHARED_LAYER_PATH:$(pwd):$PYTHONPATH"

# Print debug info
echo "PYTHONPATH: $PYTHONPATH"

# Run unit tests
echo "Running unit tests..."
if [ -z "$SPECIFIC_TEST" ]; then
    # Run all tests
    pytest tests/unit -v --cov=lambda_functions --cov-report=term-missing --cov-report=xml:coverage_reports/coverage.xml --junitxml=coverage_reports/junit.xml
else
    # Run specific test file or directory
    pytest $SPECIFIC_TEST -v --cov=lambda_functions --cov-report=term-missing --cov-report=xml:coverage_reports/coverage.xml --junitxml=coverage_reports/junit.xml
fi

echo "Unit tests completed!"
echo "Coverage report available at: coverage_reports/coverage.xml"
echo "JUnit report available at: coverage_reports/junit.xml" 