#!/bin/bash
set -e

DEPENDENCIES=(
    "click>=8.1.0,<9.0.0"
    "fastmcp>=2.0.0,<3.0.0"
    "httpx>=0.28.0,<0.29.0"
    "packaging>=24.0,<25.0"
    "pydantic>=2.0.0,<3.0.0"
    "pydantic-settings>=2.0.0,<3.0.0"
)

ARCH=$(uname -m)
echo "Detected build architecture: $ARCH"

# Upgrade pip and install dependency array
pip install --no-cache-dir --break-system-packages --upgrade pip setuptools wheel
pip install --no-cache-dir --break-system-packages "${DEPENDENCIES[@]}"

# Install specific mcp_version of the app
if [ -f /usr/local/bin/build_data/mcp_version ]; then
    MCP_VERSION=$(cat /usr/local/bin/build_data/mcp_version)
else
    echo "ERROR: /usr/local/bin/build_data/mcp_version not found!" >&2
    exit 1
fi

pip install --no-cache-dir --break-system-packages --no-deps "pypi-query-mcp-server==${MCP_VERSION}"

find /usr/lib/python* -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find /usr/lib/python* -name "*.pyc" -delete 2>/dev/null || true

python -c "import pypi_query_mcp; print('PyPI Query MCP Server imported successfully')"
pypi-query-mcp-server --help >/dev/null 2>&1 || echo "Note: pypi-query-mcp-server --help did not return cleanly (may be expected for stdio MCP)"
