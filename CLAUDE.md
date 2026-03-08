# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Isolated Crustacean runs Claude Code inside a network-isolated Docker container where all internet traffic is forced through a tinyproxy allowlist proxy. The claude-code container has no direct internet access - all outbound requests must pass through tinyproxy's domain allowlist.

## Architecture

Two Docker containers on two networks:

- **claude-code** (node:20-slim) - runs Claude Code CLI with `HTTP(S)_PROXY` pointed at tinyproxy. Connected only to the `internal` network (no default gateway, no direct internet). Workspace is a named Docker volume at `/home/<username>/workspace`; both `~/.claude/` and `~/.claude.json` are bind-mounted from the host for persistent auth/config. The container user is dynamically created to match the host user's username, UID, and GID (via `hermit` exporting `HOST_USER`, `HOST_UID`, `HOST_GID`, `HOST_HOME`). Works on both macOS (`/Users/x/`) and Linux (`/home/x/`) hosts.
- **tinyproxy** (alpine:3.21) - allowlist-filtering forward proxy on port 8888. Connected to both `internal` and `external` networks. Only allows CONNECT on port 443. No TLS interception - it cannot read API keys or conversation content.

The `internal` network is marked `internal: true` (no gateway). The `external` network is a standard bridge with internet access.

## Key Files

- `hermit` - CLI wrapper for all common operations
- `docker-compose.yml` - service definitions, network topology, volume mounts
- `claude-code/Dockerfile` - Claude Code container image (node:20-slim + git + claude-code CLI)
- `tinyproxy/Dockerfile` - proxy container image (alpine + tinyproxy)
- `tinyproxy/tinyproxy.conf` - proxy config (port 8888, ERE filter, default-deny, ConnectPort 443 only)
- `tinyproxy/allowlist` - anchored ERE regex patterns for allowed domains (one per line)

## Common Commands

Use the `hermit` wrapper script for all operations:

```bash
# Build containers
./hermit build

# Start interactive session
./hermit start

# Start with a host directory mounted
./hermit start --mount /path/to/project

# Run a command in the container
./hermit exec echo hello

# Drop into interactive bash
./hermit shell

# Workspace management (named Docker volumes)
./hermit workspace list
./hermit workspace create myproject
./hermit workspace switch myproject
./hermit workspace rm myproject

# Full rebuild (after allowlist changes, etc.)
./hermit rebuild

# Health diagnostics
./hermit doctor

# Run all isolation verification tests
./hermit test

# Show tinyproxy logs (add -f to follow, --blocked for denied only)
./hermit logs
./hermit logs -f
./hermit logs --blocked

# Stop all containers
./hermit stop

# Show container status
./hermit status
```

For reference, the underlying docker compose commands are:

```bash
docker compose build
docker compose run --rm claude-code
docker compose build tinyproxy
docker compose logs tinyproxy
docker compose ps
docker compose down
```

## Allowlist

Edit `tinyproxy/allowlist` to add/remove domains. Each line is an anchored ERE regex (e.g., `^example\.com$` for exact match, `^(.+\.)?example\.com$` to include subdomains). After changes, rebuild with `./hermit rebuild`. The filter uses `FilterDefaultDeny Yes` so only explicitly matched domains are allowed.

Default allowed domains cover: Anthropic API/auth, statsig (feature flags), sentry (error reporting), npm registry, and GitHub.

Allowlist profiles let you save/load named configurations:

```bash
./hermit allowlist profile save <name>
./hermit allowlist profile load <name>
./hermit allowlist profile list
./hermit allowlist profile rm <name>
```
