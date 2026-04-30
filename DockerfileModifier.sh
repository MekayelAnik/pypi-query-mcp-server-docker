#!/bin/bash
set -euxo pipefail

# 1. Variables and Version Check
REPO_NAME='pypi-query-mcp-server'
HAPROXY_IMAGE=$(cat ./resources/build_data/haproxy-image 2>/dev/null || echo "haproxy:lts-alpine")
NODE_IMAGE=$(cat ./resources/build_data/node-image 2>/dev/null || echo "node:lts-alpine")
BASE_IMAGE=$(cat ./resources/build_data/base-image 2>/dev/null)

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
FROM $NODE_IMAGE AS node-src
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
RUN mkdir -p /etc/haproxy/ && mv -vf /usr/local/bin/haproxy.cfg.template /etc/haproxy/haproxy.cfg.template

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/banner.sh /usr/local/bin/pypi.sh \\
    && chmod +r /usr/local/bin/build-timestamp.txt

# Alpine runtime + build helpers (shadow gives groupadd/useradd; tini for PID 1)
RUN apk add --no-cache \\
        bash ca-certificates tzdata su-exec dos2unix openssl curl wget \\
        netcat-openbsd iproute2 git libatomic libstdc++ shadow tini \\
    && dos2unix /usr/local/bin/*.sh \\
    && apk del dos2unix \\
    && ln -sf /sbin/su-exec /usr/local/bin/gosu \\
    && ln -sf /sbin/su-exec /usr/local/bin/su-exec

# HAProxy with native QUIC/H3 support from official alpine image
COPY --from=haproxy-src /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir -p /usr/local/sbin && ln -sf /usr/sbin/haproxy /usr/local/sbin/haproxy

# Node.js (musl-built) from official alpine image
COPY --from=node-src /usr/local/bin/node /usr/local/bin/node
COPY --from=node-src /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node-src /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node-src /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \\
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Create non-root user matching reference repo conventions
RUN groupadd -g 1000 node \\
    && useradd -u 1000 -g node -s /bin/bash -m node \\
    && mkdir -p /app /opt/venv \\
    && chown -R node:node /app /opt/venv /home/node /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx

USER node

# Setup Python virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:\$PATH"

# Install Python dependencies + the upstream MCP package
RUN --mount=type=cache,target=/home/node/.cache/pip,uid=1000,gid=1000 /usr/local/bin/pypi.sh

# Install supergateway globally (npm cache lives under /home/node/.npm)
RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000 \\
    npm install -g supergateway

USER root

# Cleanup transient build tools and build_data leftovers
RUN apk del curl \\
    && rm -rf /var/cache/apk/* /usr/share/man/* /usr/share/doc/* /root/.npm/_logs \\
              /usr/local/bin/pypi.sh /usr/local/bin/build_data

# Final Environment Setup
ENV PYTHONUNBUFFERED=1 \\
    PYTHONFAULTHANDLER=1 \\
    PYTHONDONTWRITEBYTECODE=1 \\
    PATH="/opt/venv/bin:\$PATH" \\
    VIRTUAL_ENV=/opt/venv \\
    PORT=8055

# L7 health check: auto-detects HTTP/HTTPS via ENABLE_HTTPS env var
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \\
    CMD sh -c 'wget -q --spider --no-check-certificate \$([ "\$ENABLE_HTTPS" = "true" ] && echo https || echo http)://127.0.0.1:\${PORT:-8055}/healthz'

ENTRYPOINT ["/sbin/tini","--","/usr/local/bin/entrypoint.sh"]
EOF
fi

echo "Successfully generated Dockerfile.$REPO_NAME"
