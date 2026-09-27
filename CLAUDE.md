# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Worktree Directory

Use `.worktrees/` (project-local, hidden) for all git worktrees.

## Project Overview

Isolated Crustacean runs Claude Code inside a network-isolated Docker container where all internet traffic is forced through a tinyproxy allowlist proxy. The claude-code container has no direct internet access - all outbound requests must pass through tinyproxy's domain allowlist.

## Architecture

Two Docker containers on two networks:

- **claude-code** (node:20-slim) - runs Claude Code CLI with `HTTP(S)_PROXY` pointed at tinyproxy. Connected only to the `internal` network (no default gateway, no direct internet). Container runs as the fixed `node` user with `WORKDIR /home/node/workspace`. The workspace is a named Docker volume (`ic-workspace`); `~/.claude/` and `~/.claude.json` are bind-mounted from the host into `/home/node/` for persistent auth/config. `hermit` exports `HOST_HOME` so bind-mount sources resolve correctly on both macOS (`/Users/x/`) and Linux (`/home/x/`) hosts.
- **tinyproxy** (alpine:3.21) - allowlist-filtering forward proxy on port 8888. Connected to both `internal` and `external` networks. Only allows CONNECT on port 443. No TLS interception - it cannot read API keys or conversation content.

The `internal` network is marked `internal: true` (no gateway). The `external` network is a standard bridge with internet access.

## Key Files

- `hermit` - CLI wrapper for all common operations
- `docker-compose.yml` - service definitions, network topology, volume mounts
- `claude-code/Dockerfile` - Claude Code container image (node:20-slim + git + claude-code CLI)
- `tinyproxy/Dockerfile` - proxy container image (alpine + tinyproxy)
- `tinyproxy/tinyproxy.conf` - proxy config: `FilterDefaultDeny Yes`, `FilterType ere`, `ConnectPort 443` only. HTTPS on 443 is the only traffic ever proxied; all other ports (including HTTP CONNECT on 80) are rejected.
- `tinyproxy/allowlist` - anchored ERE regex patterns for allowed domains (one per line)
- `mcp/templates/` - MCP server compose templates (filesystem.yml, etc.)
- `mcp/enabled/` - enabled MCP server overrides (dynamically loaded by compose_cmd helper)

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

# MCP server management
./hermit mcp list
./hermit mcp add filesystem
./hermit mcp rm filesystem
./hermit mcp status
./hermit mcp restart

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

### Running tests

`./hermit test` requires `bats-core`, `jq`, and `yq` on the host (`brew install bats-core jq yq`). It shells out to `bats tests/` after bringing up tinyproxy. To run a single suite: `bats tests/isolation.bats` (also `mcp.bats`, `allowlist.bats`, `doctor.bats`, `exec.bats`, `logs.bats`, `mount.bats`, `workspace.bats`). Shared helpers live in `tests/test_helper.bash` (`run_in_container` / `run_in_container_no_proxy`).

### Workspace selection

`./hermit workspace switch <name>` writes the name to `.hermit-workspace` in the repo root. `./hermit start` reads that file to pick the volume to mount at `/home/node/workspace`. If the file is absent, the default `ic-workspace` volume is used. `--mount <path>` overrides both.

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

## MCP Server Support

MCP (Model Context Protocol) servers can run inside the isolated network and be accessed by Claude Code.

Templates are stored in `mcp/templates/` (e.g., `filesystem.yml`). Each template defines:
- Service configuration (`build:` context under `mcp/images/<name>`, `image: ic-mcp-<name>`, expose, volumes, hardening flags)
- Network and volume references (ic-internal, ic-workspace)
- Metadata in `x-mcp` section (name, description, transport, port, path; optional `requires_env`)

Shipped templates: `filesystem`, `git`, `fetch`, `sqlite` (upstream reference servers) and `github` (official binary). All upstream servers are stdio-only, so each `mcp/images/<name>/Dockerfile` installs the pinned server package at build time and wraps it with `supergateway` (pinned) as a stdio→Streamable HTTP bridge listening on `x-mcp.port` at `x-mcp.path`. Runtime containers have no internet, so nothing may be downloaded at start. `postgres` was removed (the proxy only allows CONNECT to 443, so no database is reachable).

When you run `./hermit mcp add <server>`:
1. Hermit copies the template from `mcp/templates/<server>.yml` to `mcp/enabled/<server>.yml`
2. The enabled file is dynamically included in docker compose (via compose_cmd helper)
3. Server's internal hostname (`mcp-<server>`) is added to the proxy allowlist
4. Server is registered in `~/.claude.json` under `mcpServers`
5. The runtime workspace override is rewritten, tinyproxy (allowlist is baked into its image) and the server image are built, and `up -d tinyproxy mcp-*` runs

Set `HERMIT_NO_REBUILD=1` to skip step 5 (used by tests/scripts).

### Workspace consistency for MCP servers

`hermit start` writes `mcp/.runtime/workspace.yml` (git-ignored) via `sync_workspace_override`. It records `x-hermit.workspace_mode`/`workspace_source` and either renames the shared `workspace` volume key (named-volume mode) or replaces the `/home/node/workspace` and each MCP `/data` entry with a bind of the `--mount` path. `compose_cmd` appends it last so it wins the merge; claude-code and every enabled workspace-mounting MCP service therefore resolve to the same source. `mcp add/rm` reuse the currently pinned source (`current_workspace_source`) so a server added mid-session mounts what Claude is using. `hermit mcp sync-workspace [--mount <path>]` regenerates the file without starting Claude (tests use this).

The override also sets `NO_PROXY`/`no_proxy` on claude-code to the enabled `mcp-*` hostnames. Claude must not reach MCP servers through tinyproxy: tinyproxy has no persistent-connection support and, after relaying a streamed SSE response, forwards the client's next keep-alive request as raw proxy-form bytes (HTTP 400 from the server). Single-request access through the proxy (what the probe tests and `^mcp-<name>$` allowlist entries cover) works; Claude's multi-request sessions do not. Registration in claude.json must be `{"type": "http", "url": ...}` — Claude Code skips url-only entries.

Compose resolves relative `build:` contexts against the project directory (the first `-f` file's directory, i.e. the repo root), not the template's own directory — so templates must use `./mcp/images/<name>` and `build_mcp_images` passes `--project-directory`.

To add a new MCP server template:
1. Create `mcp/images/<name>/Dockerfile` that installs the server at build time (pinned) and runs `supergateway --stdio "<cmd>" --outputTransport streamableHttp --port <port> --streamableHttpPath /mcp`
2. Create `mcp/templates/<name>.yml` with `build: ./mcp/images/<name>`, `image: ic-mcp-<name>`, and the same hardening flags as the other templates
3. Include required `x-mcp` metadata (`name`, `description`, `transport`, `port`, `path`); parsed with yq via `mcp_meta`. Add `requires_env: VAR` if the server needs a host env var (`mcp add` warns when it is unset)
4. Name the service `mcp-<name>` — the allowlist pattern and registered URL (`http://mcp-<name>:<port><path>`) both assume this
5. Reference the `ic-internal` network (external: true); mount the workspace as `workspace:/data` and declare the `workspace` volume (name ic-workspace, external: true) if the server needs files
6. Users can then enable it with `./hermit mcp add <name>`; the `every shipped MCP template initializes through proxy` test in `tests/mcp.bats` will cover it automatically
