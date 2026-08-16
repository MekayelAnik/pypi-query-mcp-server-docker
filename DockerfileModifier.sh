#!/bin/bash
set -euxo pipefail
# Set variables first
REPO_NAME='pypi-query-mcp-server'
BASE_IMAGE=$(cat ./build_data/base-image 2>/dev/null || echo "python:3.14-alpine")
HAPROXY_IMAGE=$(cat ./build_data/haproxy-image 2>/dev/null || echo "haproxy:lts-alpine")
PQMS_VERSION=$(cat ./build_data/version 2>/dev/null || exit 1)
PQMS_PKG="pypi-query-mcp-server==${PQMS_VERSION}"
# mcp-proxy: stdio<->StreamableHTTP/SSE bridge. Replaces supergateway.
# Stateful by default (one stdio child shared across all sessions, multiplexed
# by JSON-RPC ids) — avoids the spawn-per-request memory leak that affected
# supergateway in stateless mode (supercorp-ai/supergateway#108).
MCP_PROXY_PKG=$(cat ./build_data/mcp_proxy_version 2>/dev/null || echo "mcp-proxy")
DOCKERFILE_NAME="Dockerfile.$REPO_NAME"

# Create a temporary file safely
TEMP_FILE=$(mktemp "${DOCKERFILE_NAME}.XXXXXX") || {
    echo "Error creating temporary file" >&2
    exit 1
}

# Check if this is a publication build
if [ -e ./build_data/publication ]; then
    # For publication builds, create a minimal Dockerfile that just tags the existing image
    {
        echo "ARG BASE_IMAGE=$BASE_IMAGE"
        echo "ARG PQMS_VERSION=$PQMS_VERSION"
        echo "FROM $BASE_IMAGE"
    } > "$TEMP_FILE"
else
    # Write the Dockerfile content to the temporary file first
    {
        echo "ARG BASE_IMAGE=$BASE_IMAGE"
        echo "ARG PQMS_VERSION=$PQMS_VERSION"
        cat << EOF
FROM $HAPROXY_IMAGE AS haproxy-src
FROM $BASE_IMAGE AS build

# Author info:
LABEL org.opencontainers.image.authors="MOHAMMAD MEKAYEL ANIK <mekayel.anik@gmail.com>"
LABEL org.opencontainers.image.description="PyPI Query MCP Server — query PyPI package metadata, dependencies, and download stats with mcp-proxy (stdio<->StreamableHTTP/SSE bridge)"
LABEL org.opencontainers.image.source="https://github.com/mekayelanik/pypi-query-mcp-server-docker"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later"

# Copy the entrypoint script into the container and make it executable
COPY ./resources/ /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/banner.sh \\
    && if [ -f /usr/local/bin/build-timestamp.txt ]; then chmod +r /usr/local/bin/build-timestamp.txt; fi \\
    && mkdir -p /etc/haproxy \\
    && mv -vf /usr/local/bin/haproxy.cfg.template /etc/haproxy/haproxy.cfg.template \\
    && ls -la /etc/haproxy/haproxy.cfg.template

# Install required APK packages. python alpine base ships python3+pip; we only
# need the system-level utilities below. No nodejs/npm — mcp-proxy is pure Python.
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \\
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \\
    apk --update-cache --no-cache add bash shadow su-exec tzdata haproxy netcat-openbsd openssl wget ca-certificates util-linux && \\
    rm -rf /var/cache/apk/*

# HAProxy with native QUIC/H3 support from official image
COPY --from=haproxy-src /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir -p /usr/local/sbin && ln -sf /usr/sbin/haproxy /usr/local/sbin/haproxy

# Install pypi-query-mcp-server + mcp-proxy from PyPI in one layer (shared pip cache).
# mcp-proxy replaces supergateway as the stdio<->HTTP bridge (pure Python, no Node).
RUN --mount=type=cache,target=/root/.cache/pip \\
    echo "Installing packages: ${PQMS_PKG} + ${MCP_PROXY_PKG}" && \\
    pip install --no-cache-dir --break-system-packages ${PQMS_PKG} ${MCP_PROXY_PKG} && \\
    echo "Packages installed successfully" && \\
    mcp-proxy --version

# Use an ARG for the default port
ARG PORT=8055

# Add ARG for API key
ARG API_KEY=""

# Set an ENV variable from the ARG for runtime
ENV PORT=\${PORT}
ENV API_KEY=\${API_KEY}

# L7 health check: auto-detects HTTP/HTTPS via ENABLE_HTTPS env var.
# /healthz is answered by HAProxy locally (mcp-proxy lacks a configurable
# health endpoint) so the check itself returns in well under a second.
# start-period=60s tolerates the cold-start period so orchestrators do not
# flap the container before the backend is ready.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
    CMD sh -c 'wget -q --spider --no-check-certificate \$([ "\$ENABLE_HTTPS" = "true" ] && echo https || echo http)://127.0.0.1:\${PORT:-8055}/healthz'

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EOF
    } > "$TEMP_FILE"
fi

# Atomically replace the target file with the temporary file
if mv -f "$TEMP_FILE" "$DOCKERFILE_NAME"; then
    echo "Dockerfile for $REPO_NAME created successfully."
else
    echo "Error: Failed to create Dockerfile for $REPO_NAME" >&2
    rm -f "$TEMP_FILE"
    exit 1
fi
