#!/bin/bash
set -e

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Virtual environment not found. Creating one..."
    python -m venv venv
    . venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements-dev.txt
else
    if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
        . venv/bin/activate
    elif [ "$(uname)" == "Windows" ]; then
        . venv/Scripts/activate
    fi
fi

# Run linting
echo "Running flake8..."
flake8 lambda_functions tests --ignore=E501,E402,W503

echo "Running black in check mode..."
black --check lambda_functions tests

echo "If you want to automatically format your code with black, run: ./scripts/format.sh" 