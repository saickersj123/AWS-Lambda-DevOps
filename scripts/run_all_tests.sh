#!/bin/bash
set -e

# Default environment if not specified
ENV=${1:-dev}

echo "=================================="
echo "Running all tests (unit + integration)"
echo "=================================="

# Run unit tests first
echo "Running unit tests..."
./scripts/run_unit_tests.sh
UNIT_TEST_STATUS=$?

echo "=================================="

# Run integration tests if unit tests pass
if [ $UNIT_TEST_STATUS -eq 0 ]; then
    echo "Running integration tests against $ENV environment..."
    ./scripts/run_integration_tests.sh $ENV
    INTEGRATION_TEST_STATUS=$?
else
    echo "Unit tests failed. Skipping integration tests."
    INTEGRATION_TEST_STATUS=1
fi

echo "=================================="
echo "All tests completed!"

# Exit with failure if any test failed
if [ $UNIT_TEST_STATUS -ne 0 ] || [ $INTEGRATION_TEST_STATUS -ne 0 ]; then
    echo "Some tests failed."
    exit 1
else
    echo "All tests passed!"
    exit 0
fi 