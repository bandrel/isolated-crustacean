# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Isolated Crustacean runs Claude Code inside a network-isolated Docker container where all internet traffic is forced through a tinyproxy allowlist proxy. The claude-code container has no direct internet access - all outbound requests must pass through tinyproxy's domain allowlist.

## Architecture

Two Docker containers on two networks:

- **claude-code** (node:20-slim) - runs Claude Code CLI with `HTTP(S)_PROXY` pointed at tinyproxy. Connected only to the `internal` network (no default gateway, no direct internet). Workspace is a named Docker volume at `/home/node/workspace`; `~/.claude` is bind-mounted from the host for persistent auth/config.
- **tinyproxy** (alpine:3.21) - allowlist-filtering forward proxy on port 8888. Connected to both `internal` and `external` networks. Only allows CONNECT on port 443. No TLS interception - it cannot read API keys or conversation content.

The `internal` network is marked `internal: true` (no gateway). The `external` network is a standard bridge with internet access.

## Key Files

- `docker-compose.yml` - service definitions, network topology, volume mounts
- `claude-code/Dockerfile` - Claude Code container image (node:20-slim + git + claude-code CLI)
- `tinyproxy/Dockerfile` - proxy container image (alpine + tinyproxy)
- `tinyproxy/tinyproxy.conf` - proxy config (port 8888, ERE filter, default-deny, ConnectPort 443 only)
- `tinyproxy/allowlist` - anchored ERE regex patterns for allowed domains (one per line)

## Common Commands

```bash
# Build containers
docker compose build

# Start interactive session
docker compose run --rm claude-code

# Rebuild only the proxy (e.g. after editing allowlist)
docker compose build tinyproxy

# Verify isolation - direct access should fail
docker compose run --rm claude-code -c "curl -s --max-time 5 https://google.com"

# Verify isolation - non-allowlisted domain should get 403
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://google.com"

# Verify isolation - allowlisted domain should succeed
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://api.anthropic.com"

# Check proxy logs
docker compose logs tinyproxy
```

## Allowlist

Edit `tinyproxy/allowlist` to add/remove domains. Each line is an anchored ERE regex (e.g., `^example\.com$` for exact match, `^(.+\.)?example\.com$` to include subdomains). After changes, rebuild with `docker compose build tinyproxy`. The filter uses `FilterDefaultDeny Yes` so only explicitly matched domains are allowed.

Default allowed domains cover: Anthropic API/auth, statsig (feature flags), sentry (error reporting), npm registry, and GitHub.
