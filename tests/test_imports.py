"""
Test file to check if the imports are working correctly.
"""

import os  # noqa: F401
import sys

import pytest


def test_sys_path():
    """Test that the Python path is set up correctly."""
    print(f"Python path: {sys.path[:10]}")  # Show first 10 entries in sys.path

    # Print the Python path and check if the key directories are included
    path_str = ";".join(sys.path)
    assert (
        "lambda/shared_layer/python" in path_str
        or "lambda\\shared_layer\\python" in path_str
    ), "shared_layer/python not in Python path"

    # Check if we can import from the shared layer
    try:
        # Try using direct import
        import common_utils  # noqa: F401

        print("✅ Successfully imported common_utils directly")
    except ImportError as e:
        print(f"Failed to import common_utils directly: {e}")
        pytest.fail("Failed to import common_utils")

    print("Import test passed successfully")
