#!/bin/bash
set -e

echo "Setting up development environment..."

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python -m venv venv
else
    echo "Virtual environment already exists."
fi

# Activate virtual environment
echo "Activating virtual environment..."
if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
    #for Linux
    . venv/bin/activate 
elif [ "$(uname)" == "Windows" ]; then
    #for Windows
    . venv/Scripts/activate
fi

# Install dependencies
echo "Installing development dependencies..."
if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
    #for Linux
    pip install --upgrade pip
    pip install -r requirements-dev.txt
elif [ "$(uname)" == "Windows" ]; then
    #for Windows
    python -m pip install --upgrade pip
    python -m pip install -r requirements-dev.txt
fi

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
if [ "$(uname)" == "Darwin" ] || [ "$(uname)" == "Linux" ]; then
    #for Linux
    pre-commit install
elif [ "$(uname)" == "Windows" ]; then
    #for Windows
    pre-commit install
fi

echo "Development environment setup complete!"
echo "You can now run these commands:"
echo "  - ./scripts/lint.sh      # Check code for linting issues"
echo "  - ./scripts/format.sh    # Format code automatically"
echo "Development environment is ready!" 