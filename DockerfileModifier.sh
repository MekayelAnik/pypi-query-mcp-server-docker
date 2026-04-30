#!/bin/bash
set -euxo pipefail

# 1. Variables and Version Check
REPO_NAME='pypi-query-mcp-server'
HAPROXY_IMAGE=$(cat ./resources/build_data/haproxy-image 2>/dev/null || echo "haproxy:lts-alpine")
BASE_IMAGE=$(cat ./resources/build_data/base-image 2>/dev/null || echo "python:3.14-alpine")

# Create Dockerfile directly
if [ -e ./resources/build_data/publication ]; then
    # For publication builds
    echo "FROM ${BASE_IMAGE}" > "Dockerfile.$REPO_NAME"
    echo "# Publication tag" >> "Dockerfile.$REPO_NAME"
else
    if [ -f ./resources/build_data/mcp_version ]; then
        MCP_VERSION=$(cat ./resources/build_data/mcp_version)
        echo "Building Dockerfile for $MCP_VERSION"
    else
        echo "ERROR: build_data/mcp_version not found!" >&2
        exit 1
    fi

# 4. Generate the Dockerfile
cat > "Dockerfile.$REPO_NAME" << EOF
FROM $HAPROXY_IMAGE AS haproxy-src
FROM ${BASE_IMAGE}

# Author and image metadata
LABEL org.opencontainers.image.authors="MOHAMMAD MEKAYEL ANIK <mekayel.anik@gmail.com>"
LABEL org.opencontainers.image.title="pypi-query-mcp-server"
LABEL org.opencontainers.image.description="PyPI Query MCP Server with Supergateway (HAProxy QUIC/H3 fronted, stdio/SSE/SHTTP)"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later"
LABEL org.opencontainers.image.source="https://github.com/MekayelAnik/pypi-query-mcp-server-docker"
LABEL org.opencontainers.image.url="https://hub.docker.com/r/mekayelanik/pypi-query-mcp-server"
LABEL org.opencontainers.image.vendor="Mohammad Mekayel Anik"
LABEL org.opencontainers.image.version="$MCP_VERSION"

# Copy scripts and build data into the image
COPY ./resources/ /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/banner.sh /usr/local/bin/pypi.sh \\
    && if [ -f /usr/local/bin/build-timestamp.txt ]; then chmod +r /usr/local/bin/build-timestamp.txt; fi \\
    && mkdir -p /etc/haproxy \\
    && mv -vf /usr/local/bin/haproxy.cfg.template /etc/haproxy/haproxy.cfg.template

# Alpine runtime + Node.js for supergateway (single repo set; mirrors valkey/openapi pattern)
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \\
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \\
    apk --update-cache --no-cache add \\
        bash shadow su-exec tzdata haproxy netcat-openbsd openssl wget ca-certificates \\
        nodejs npm && \\
    rm -rf /var/cache/apk/*

# HAProxy with native QUIC/H3 support from official alpine image
COPY --from=haproxy-src /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir -p /usr/local/sbin && ln -sf /usr/sbin/haproxy /usr/local/sbin/haproxy

# Install upstream pypi-query-mcp-server from PyPI (cache mount reuses pip downloads)
RUN --mount=type=cache,target=/root/.cache/pip /usr/local/bin/pypi.sh

# Install Supergateway (cache mount shares npm cache)
RUN --mount=type=cache,target=/root/.npm \\
    npm install -g supergateway --omit=dev --no-audit --no-fund --loglevel error && \\
    rm -rf /tmp/* /var/tmp/* \\
           /usr/local/lib/node_modules/npm/man /usr/local/lib/node_modules/npm/docs /usr/local/lib/node_modules/npm/html

# Cleanup build-only files (pypi.sh + build_data baked in by COPY ./resources/ above)
RUN rm -rf /usr/local/bin/pypi.sh /usr/local/bin/build_data

# Use an ARG for the default port + API key (matches sibling repos)
ARG PORT=8055
ARG API_KEY=""
ENV PORT=\${PORT}
ENV API_KEY=\${API_KEY}

# L7 health check: auto-detects HTTP/HTTPS via ENABLE_HTTPS env var
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \\
    CMD sh -c 'wget -q --spider --no-check-certificate \$([ "\$ENABLE_HTTPS" = "true" ] && echo https || echo http)://127.0.0.1:\${PORT:-8055}/healthz'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOF
fi

echo "Successfully generated Dockerfile.$REPO_NAME"
