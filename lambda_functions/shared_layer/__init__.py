"""
Shared utilities and dependencies used across Lambda functions.
"""

# Import common modules that should be available when importing shared_layer
try:
    from . import common_utils  # noqa: F401
except ImportError:
    # During testing, common_utils might be imported directly
    pass
