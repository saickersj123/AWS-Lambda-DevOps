"""
Helper module to set AWS environment variables before importing AWS-dependent modules.
This ensures tests don't fail due to missing AWS configuration.
"""

import os
import sys


def configure_aws_environment():
    """Set AWS environment variables for testing."""
    # Set AWS environment variables if not already set
    os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-2")
    os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
    os.environ.setdefault("AWS_SECURITY_TOKEN", "testing")
    os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
    os.environ.setdefault("ENVIRONMENT", "test")

    # Add to Python path if needed
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    lambda_dir = os.path.join(project_root, "lambda")
    shared_layer_path = os.path.join(lambda_dir, "shared_layer")
    shared_layer_python_path = os.path.join(shared_layer_path, "python")

    paths_to_add = [
        project_root,
        lambda_dir,
        shared_layer_path,
        shared_layer_python_path,
    ]

    for path in paths_to_add:
        if path not in sys.path:
            sys.path.insert(0, path)

    # Print debug info
    print(f"AWS_DEFAULT_REGION: {os.environ.get('AWS_DEFAULT_REGION')}")
    print(f"PYTHONPATH: {sys.path[:3]}")  # Show first 3 entries


# Run configuration when this module is imported
configure_aws_environment()
