# PyPI Query MCP Server — Docker Image

[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/MekayelAnik/pypi-query-mcp-server-docker/monitor-npm-releases.yml?label=build)](https://github.com/MekayelAnik/pypi-query-mcp-server-docker/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/mekayelanik/pypi-query-mcp-server.svg)](https://hub.docker.com/r/mekayelanik/pypi-query-mcp-server)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A self-contained, multi-architecture (`linux/amd64`, `linux/arm64`) Docker image that runs the upstream [`pypi-query-mcp-server`](https://github.com/loonghao/pypi-query-mcp-server) Model Context Protocol server, wrapped by [`supergateway`](https://github.com/supercorp-ai/supergateway) and fronted by HAProxy with native QUIC / HTTP/3 support, optional TLS, Bearer-token auth, IP allow/block lists, CORS, and rate-limiting.

The upstream MCP server speaks **stdio**. Inside the container, supergateway bridges stdio to a network listener; HAProxy then exposes the chosen transport (SSE, Streamable HTTP, or WebSocket) on the published port. MCP clients (Claude Desktop, Claude Code, Cline, Cursor, Windsurf, etc.) can connect over **stdio** (via `docker exec`), **SSE**, or **Streamable HTTP**.

---

## Acknowledgments / Upstream Credit

This Docker image is a packaging and runtime-orchestration layer over the work of the upstream project authors. **All MCP functionality (tools, prompt templates, PyPI queries, dependency resolution, download statistics, etc.) is implemented entirely upstream — not by this repository.**

| Component | Author / Project | License | Link |
|---|---|---|---|
| `pypi-query-mcp-server` (the MCP server) | [loonghao](https://github.com/loonghao) | MIT | [GitHub](https://github.com/loonghao/pypi-query-mcp-server) · [PyPI](https://pypi.org/project/pypi-query-mcp-server/) |
| `supergateway` (stdio ↔ SSE/SHTTP/WS bridge) | [Supercorp](https://github.com/supercorp-ai/supergateway) | see upstream | [GitHub](https://github.com/supercorp-ai/supergateway) |
| HAProxy (TLS, QUIC, HTTP/3, ACLs) | Willy Tarreau & contributors | GPLv2 | [haproxy.org](https://www.haproxy.org/) |
| Node.js | OpenJS Foundation | MIT | [nodejs.org](https://nodejs.org/) |
| Python | Python Software Foundation | PSF | [python.org](https://www.python.org/) |
| Alpine Linux base | Alpine Linux contributors | mixed | [alpinelinux.org](https://alpinelinux.org/) |

**Please cite, star, and report MCP-server bugs to the [upstream repository](https://github.com/loonghao/pypi-query-mcp-server).** Bugs in the Docker packaging, entrypoint, HAProxy wrapper, or build pipeline belong here.

## Disclaimer (Non-Affiliation)

This Docker image and the build/wrapper code in this repository are **independently produced and maintained by Mohammad Mekayel Anik**. This project is **NOT affiliated with, endorsed by, sponsored by, or otherwise officially connected to**:

- `loonghao` or any contributor of the upstream `pypi-query-mcp-server` project.
- The Supergateway authors.
- HAProxy Technologies, the HAProxy project, or Willy Tarreau.
- The OpenJS Foundation, the Python Software Foundation, or Alpine Linux.

All trademarks, product names, and project names referenced are the property of their respective owners. Reference is for accurate identification only and does not imply any commercial relationship.

---

## What's Inside

- **Base image**: `python:3.14-alpine` (musl-based, ~50MB before app layers)
- **Python venv** at `/opt/venv` with the upstream MCP server installed from PyPI
- **Node.js (LTS)** copied from `node:lts-alpine` for the supergateway bridge
- **HAProxy (LTS, alpine)** copied from `haproxy:lts-alpine` — built with native QUIC/HTTP-3 support
- **`tini`** as PID 1 for proper signal forwarding
- Non-root runtime user `node` (UID/GID `1000:1000`, overridable via `PUID`/`PGID`)
- Auto-detected QUIC/H3 capability with graceful HTTP/2 + HTTP/1.1 fallback
- Self-signed TLS generation on first run (or bring your own PEM)
- Healthcheck on `/healthz`

## Image Tags

```
mekayelanik/pypi-query-mcp-server:latest                  # latest stable PyPI release
mekayelanik/pypi-query-mcp-server:<version>               # specific release, e.g. 0.6.5
mekayelanik/pypi-query-mcp-server:<version>-DDMMYYYY      # pinned to a specific build date
ghcr.io/mekayelanik/pypi-query-mcp-server:<tag>           # GHCR mirror, identical content
```

The `latest` tag tracks the newest stable release published to PyPI. A scheduled GitHub Actions workflow monitors `https://pypi.org/pypi/pypi-query-mcp-server/json` and rebuilds on new releases.

## Quick Start

### docker run (Streamable HTTP, the default)

```bash
docker run -d \
  --name pypi-query-mcp-server \
  -p 8055:8055 \
  -e PROTOCOL=SHTTP \
  -e PORT=8055 \
  --restart unless-stopped \
  mekayelanik/pypi-query-mcp-server:latest
```

Then point an MCP client at `http://localhost:8055/mcp`.

### docker compose

```yaml
services:
  pypi-query-mcp-server:
    image: mekayelanik/pypi-query-mcp-server:latest
    container_name: pypi-query-mcp-server
    environment:
      - PORT=8055
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - PROTOCOL=SHTTP
      - ENABLE_HTTPS=false
      - HTTP_VERSION_MODE=auto
      # - API_KEY=replace-with-strong-secret
      # - CORS=*
    ports:
      - "8055:8055"
    volumes:
      - pypi-query-mcp-cache:/home/node/.cache
    restart: unless-stopped

volumes:
  pypi-query-mcp-cache:
    driver: local
```

```bash
docker compose up -d
```

## Supported Transports

| `PROTOCOL` value | Path on `PORT` | Notes |
|---|---|---|
| `SHTTP` (default) | `POST /mcp` | Streamable HTTP — recommended for browser/long-running clients |
| `SSE` | `GET /sse` | Server-Sent Events — compatible with most MCP clients |
| `WS` | `GET /message` | WebSocket — useful for low-latency bidirectional streams |
| stdio (no `PROTOCOL`) | n/a | Run via `docker exec -i ... pypi-query-mcp-server` and pipe stdio directly |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8055` | External HAProxy listen port |
| `PUID` | `1000` | UID for the runtime user |
| `PGID` | `1000` | GID for the runtime user |
| `TZ` | `UTC` | Timezone (e.g. `Asia/Dhaka`) |
| `PROTOCOL` | `SHTTP` | One of `SHTTP`, `SSE`, `WS` |
| `ENABLE_HTTPS` | `false` | Set `true` to terminate TLS at HAProxy |
| `HTTP_VERSION_MODE` | `auto` | `auto`, `h1`, `h2`, `h3` — pin or auto-detect HTTP version |
| `API_KEY` | _(unset)_ | If set, requires `Authorization: Bearer <key>` on every request (5–256 chars, no whitespace) |
| `CORS` | _(unset)_ | Comma-separated origins or `*` |
| `IP_ALLOWLIST` | _(unset)_ | Comma-separated CIDRs/IPs |
| `IP_BLOCKLIST` | _(unset)_ | Comma-separated CIDRs/IPs |
| `RATE_LIMIT` | _(unset)_ | Requests per period, e.g. `100/1m` |
| `TLS_DAYS` | `365` | Validity (days) for self-signed cert |
| `TLS_CN` | `localhost` | Common Name for self-signed cert |
| `TLS_MIN_VERSION` | `TLSv1.3` | One of `TLSv1.2`, `TLSv1.3` |
| `TLS_CERT` / `TLS_KEY` | _(unset)_ | Bring-your-own PEM (mounted into container) |
| Upstream env vars | _(see below)_ | Passed through to the MCP server |

### Upstream MCP Server Configuration

The upstream `pypi-query-mcp-server` reads its own configuration from environment variables (see [upstream README](https://github.com/loonghao/pypi-query-mcp-server#environment-variables) for full list). All such variables are passed through unchanged. Common ones:

- `PYPI_INDEX_URL` — primary PyPI index (default `https://pypi.org/simple/`)
- `PYPI_EXTRA_INDEX_URLS` — comma-separated mirrors
- `PYPI_INDEX_USERNAME`, `PYPI_INDEX_PASSWORD` — for private indexes
- `PYPI_CACHE_TTL` — cache duration in seconds

## MCP Client Configuration

### Claude Desktop / Cursor / Windsurf (Streamable HTTP)

```json
{
  "mcpServers": {
    "pypi-query": {
      "url": "http://localhost:8055/mcp",
      "transport": "streamableHttp"
    }
  }
}
```

### Claude Desktop (SSE)

```json
{
  "mcpServers": {
    "pypi-query": {
      "url": "http://localhost:8055/sse",
      "transport": "sse"
    }
  }
}
```

### Claude Desktop (stdio via docker)

```json
{
  "mcpServers": {
    "pypi-query": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "mekayelanik/pypi-query-mcp-server:latest",
        "/opt/venv/bin/pypi-query-mcp-server"
      ]
    }
  }
}
```

### With API Key

If you set `API_KEY` on the container, clients must add an `Authorization: Bearer <key>` header. For Claude Desktop, set the header in the client's HTTP transport config (varies by client version).

## Available MCP Tools

The upstream MCP server exposes 24 tools and prompt templates (subject to change in newer versions). Highlights:

- **`get_package_info`** — comprehensive PyPI package info
- **`get_package_versions`** — list all versions of a package
- **`get_package_dependencies`** — analyze direct dependencies
- **`check_package_python_compatibility`** — Python version compatibility check
- **`resolve_dependencies`** — recursive dependency resolution
- **`download_package`** — download package + dependencies
- **`get_download_statistics`** — download counts (BigQuery-backed)
- **`get_download_trends`** — 180-day trend series
- **`get_top_downloaded_packages`** — popularity ranking
- Prompt templates: `analyze_package_quality`, `compare_packages`, `suggest_alternatives`, `resolve_dependency_conflicts`, `plan_version_upgrade`, `audit_security_risks`, etc.

See the [upstream README](https://github.com/loonghao/pypi-query-mcp-server#available-mcp-tools) for the authoritative list and detailed semantics.

## Healthcheck

The container ships a Docker `HEALTHCHECK` that probes `http(s)://127.0.0.1:${PORT}/healthz`. The `/healthz` endpoint is bypassed from auth/rate-limit so monitors can call it freely.

```bash
docker inspect --format='{{.State.Health.Status}}' pypi-query-mcp-server
```

## Building Locally

```bash
git clone https://github.com/MekayelAnik/pypi-query-mcp-server-docker.git
cd pypi-query-mcp-server-docker

mkdir -p resources/build_data
echo 'python:3.14-alpine'   > resources/build_data/base-image
echo 'haproxy:lts-alpine'   > resources/build_data/haproxy-image
echo 'node:lts-alpine'      > resources/build_data/node-image
echo '0.6.5'                > resources/build_data/mcp_version
date -u +%Y-%m-%dT%H:%M:%SZ > resources/build-timestamp.txt

bash DockerfileModifier.sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.pypi-query-mcp-server \
  -t pypi-query-mcp-server:dev .
```

## CI / CD

The repository ships a complete CI/CD setup mirroring its sibling MCP-image repos:

- `.github/workflows/monitor-npm-releases.yml` — daily PyPI poll + on-demand `workflow_dispatch`
- `.github/workflows/reusable-build-versions.yml` — matrix build across versions × platforms with skip-if-already-pushed and crane-based digest checks
- `.github/workflows/reusable-promote-latest.yml` — atomically promote a specific version to `:latest` across both registries
- `.github/workflows/update-dockerhub-readme.yml` — sync this README to Docker Hub
- 7 composite actions under `.github/actions/` (registry login, sync, retry build/push, profile resolution, etc.)
- 9 shell scripts under `.github/scripts/` for tag-existence checks, registry sync, runtime smoke tests

### Required Repository Variables / Secrets

| Setting | Type | Purpose |
|---|---|---|
| `DOCKERHUB_USERNAME` | secret | Docker Hub login |
| `DOCKERHUB_TOKEN` | secret | Docker Hub access token (write) |
| `DOCKERHUB_REPO` | var (optional) | Override `mekayelanik/pypi-query-mcp-server` |
| `GHCR_REPO` | var (optional) | Override `ghcr.io/<owner>/pypi-query-mcp-server` |
| `BASE_IMAGE_DEFAULT` | var (optional) | Override `python:3.14-alpine` |
| `HAPROXY_IMAGE` | var (optional) | Override `haproxy:lts-alpine` |
| `NODE_IMAGE` | var (optional) | Override `node:lts-alpine` |
| `DEFAULT_PLATFORMS` | var (optional) | Override `linux/amd64,linux/arm64` |
| `TZ` | var (optional) | Default `Asia/Dhaka` |

`GITHUB_TOKEN` is auto-provided by Actions for GHCR pushes.

## License

This Docker image and its build/wrapper code are licensed under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later). See [LICENSE](LICENSE) for full text and ATTRIBUTIONS.

The GPL-3.0 covers ONLY the wrapper code authored in this repository. The upstream MCP server, supergateway, HAProxy, Node.js, Python, and Alpine Linux components retain their own licenses (see [Acknowledgments](#acknowledgments--upstream-credit)).

> **Note for image consumers:** Mere _use_ of the resulting image (running it as a container) does not trigger GPLv3 obligations. Redistribution of modified versions of the wrapper code does.

## Issues / Contributing

- **MCP server bugs / feature requests** → [upstream issue tracker](https://github.com/loonghao/pypi-query-mcp-server/issues)
- **Docker image / packaging / CI bugs** → [this repo's issues](https://github.com/MekayelAnik/pypi-query-mcp-server-docker/issues)

PRs welcome. Run shellcheck + `bash -n` on any modified shell script before submitting; the preflight CI job will reject otherwise.

## Maintainer

Mohammad Mekayel Anik — `mekayel.anik@gmail.com`
