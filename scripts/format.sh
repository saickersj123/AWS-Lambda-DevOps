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

# Run formatters
echo "Running black formatter..."
black lambda_functions tests

echo "Running isort formatter..."
isort lambda_functions tests

echo "Code formatting complete!" 