# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Worktree Directory

Use `.worktrees/` (project-local, hidden) for all git worktrees.

## Project Overview

Isolated Crustacean runs Claude Code inside a network-isolated Docker container where all internet traffic is forced through a tinyproxy allowlist proxy. The claude-code container has no direct internet access - all outbound requests must pass through tinyproxy's domain allowlist.

## Architecture

Three Docker containers on two networks:

- **claude-code** (node:24-bookworm-slim) - runs Claude Code CLI with `HTTP(S)_PROXY` pointed at tinyproxy, but the actual enforcement boundary is the network: connected only to the `internal` network (marked `internal: true`, which has no default gateway, so no direct internet route exists regardless of proxy env vars). Container runs as the fixed `node` user with `WORKDIR /home/node/workspace`. The workspace is a named Docker volume (`ic-workspace`, git-ignored override via `mcp/.runtime/workspace.yml`); `~/.claude/` and `~/.claude.json` are bind-mounted from `$HERMIT_CONFIG_DIR` (default `~/.hermit/`) on the host into `/home/node/` for persistent auth/config.
- **tinyproxy** (alpine:3.22) - allowlist-filtering forward proxy on port 8888. Connected to both `internal` and `external` networks. Explicit forward proxy (not transparent/MITM). Restricts CONNECT requests to port 443 only. Plain-HTTP forwarding (not port-restricted) allows probe to reach allowlisted hosts via HTTP. No TLS interception — it cannot read API keys or conversation content.
- **probe** (debian:bookworm-slim) - isolation verification test harness, runs in profile "probe". Used by `./hermit test` and `./hermit doctor` to verify proxy connectivity and DNS behavior via curl/dnsutils.

The `internal` network is marked `internal: true` (no gateway). The `external` network is a standard bridge with internet access.

## Key Files

- `hermit` - CLI wrapper for all common operations (workspace, MCP, allowlist, compose helpers)
- `docker-compose.yml` - service definitions, network topology, volume mounts for claude-code, tinyproxy, and probe
- `claude-code/Dockerfile` - Claude Code container image (node:24-bookworm-slim + git + claude-code CLI). Installs Claude Code at a pinned version via ARG CLAUDE_CODE_VERSION.
- `tinyproxy/Dockerfile` - proxy container image (alpine:3.22 + tinyproxy). Runs as nobody:nogroup with tmpfs-backed logs and runtime socket dirs.
- `tinyproxy/tinyproxy.conf` - proxy config: `FilterDefaultDeny Yes`, `FilterType ere`, `ConnectPort 443`. Restricts CONNECT to 443 only. Plain-HTTP forwarding is not port-restricted; probe uses this for single-request connectivity tests.
- `tinyproxy/allowlist` - anchored ERE regex patterns for allowed domains (one per line), baked into the tinyproxy image at build time.
- `probe/Dockerfile` - test harness container image (debian:bookworm-slim + curl + dnsutils). Runs commands that `tests/*.bats` and `./hermit doctor` invoke via `compose_cmd run --rm probe`.
- `mcp/templates/` - MCP server compose service templates (filesystem.yml, git.yml, fetch.yml, sqlite.yml, github.yml) with `x-mcp` metadata
- `mcp/enabled/` - enabled MCP server overrides (dynamically loaded last by compose_cmd, so they win the merge and their port claims don't clash with templates)
- `mcp/images/<name>/Dockerfile` - build context for each MCP server image; installs the pinned server package and wraps it with supergateway as a stdio→Streamable-HTTP bridge
- `mcp/.runtime/workspace.yml` - git-ignored, generated at runtime by hermit. Pins workspace source (named volume or --mount path) for claude-code and every enabled workspace-mounting MCP service. Also sets NO_PROXY on claude-code to enabled mcp-* hostnames.
- `tests/test_helper.bash` - shared test helper functions (`run_in_container`, `run_in_container_no_proxy`, `run_in_claude_container`)
- `tests/*.bats` - BATS test suites for isolation, MCP, allowlist, doctor, exec, logs, mount, and workspace functionality

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

`./hermit test` requires `bats-core`, `jq`, and `yq` on the host (`brew install bats-core jq yq`). It shells out to `bats tests/` after bringing up tinyproxy; probe service runs per test. To run a single suite: `bats tests/isolation.bats` (also `mcp.bats`, `allowlist.bats`, `doctor.bats`, `exec.bats`, `logs.bats`, `mount.bats`, `workspace.bats`). Shared helpers live in `tests/test_helper.bash`:
- `run_in_container <cmd>` - run command in probe container with proxy env set
- `run_in_container_no_proxy <cmd>` - run command in probe container without proxy env
- `run_in_claude_container <cmd>` - run command in claude-code container with proxy env set

### Workspace selection

Workspaces are Docker named volumes with a prefix for isolation: `isolated-crustacean-<name>` for new volumes. The script supports a legacy prefix `isolated-crustaion-<name>` (note the typo) as a fallback for backward compatibility; existing volumes with the legacy prefix are still recognized and can be switched to.

`./hermit workspace switch <name>` writes the name to `.hermit-workspace` in the repo root. `./hermit start` reads that file to determine which named volume to use; if the file is absent, the default `ic-workspace` volume is used. `--mount <path>` overrides both, binding the host directory instead.

`./hermit workspace current` prints the resolved volume name for the currently selected workspace (e.g., `isolated-crustacean-<name>` for named workspaces or `ic-workspace` for default).

At runtime, `hermit start` writes `mcp/.runtime/workspace.yml` which pins the active workspace source for both claude-code and every enabled MCP service, so they always see the same files. The override also sets `NO_PROXY` on claude-code to the enabled `mcp-*` hostnames so Claude connects directly to MCP servers over `ic-internal` without going through tinyproxy.

For reference, the underlying docker compose commands are:

```bash
docker compose build
docker compose run --rm claude-code
docker compose build tinyproxy
docker compose logs tinyproxy
docker compose ps
docker compose down
```

## Hardening

The `hermit` script uses `set -euo pipefail`: `-e` exits on any error, `-u` treats undefined variables as errors, `-o pipefail` fails the pipeline if any stage fails.

All services in `docker-compose.yml` and MCP service templates are hardened with:
- `cap_drop: [ALL]` - no Linux capabilities (most restrictive baseline)
- `security_opt: [no-new-privileges:true]` - prevent privilege escalation via setuid/setgid
- `read_only: true` - immutable filesystem (except tmpfs mounts)
- `tmpfs` with writable scratch space (specific paths set in `docker-compose.yml` per service, e.g., `/tmp`, `/home/node/.cache`, `/var/log/tinyproxy`, `/var/run/tinyproxy`)
- `pids_limit: 512` (or 100–256 depending on workload) - prevent fork bombs

These are specified in `docker-compose.yml` at the service level, not in Dockerfiles (tmpfs cannot be set in images).

## Allowlist

Edit `tinyproxy/allowlist` to add/remove domains. Each line is an anchored ERE regex (e.g., `^example\.com$` for exact match, `^(.+\.)?example\.com$` to include subdomains). After changes, rebuild with `./hermit rebuild`. The filter uses `FilterDefaultDeny Yes` so only explicitly matched domains are allowed.

Default allowed domains cover: Anthropic API/auth, npm registry, and GitHub. Claude Code sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` to suppress feature flags, error reporting, and other non-essential traffic.

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

Shipped templates: `filesystem`, `git`, `fetch`, `sqlite` (upstream reference servers) and `github` (official binary). All upstream servers are stdio-only, so each `mcp/images/<name>/Dockerfile` installs the pinned server package at build time and wraps it with `supergateway` (pinned) as a stdio→Streamable HTTP bridge listening on `x-mcp.port` at `x-mcp.path`. Runtime containers have no internet, so nothing may be downloaded at start.

When you run `./hermit mcp add <server>`:
1. Hermit copies the template from `mcp/templates/<server>.yml` to `mcp/enabled/<server>.yml`
2. The enabled file is dynamically included in docker compose (via compose_cmd helper)
3. Server's internal hostname (`mcp-<server>`) is added to the proxy allowlist (baked into tinyproxy image at build time)
4. Server is registered in `$HERMIT_CONFIG_DIR/claude.json` (default `~/.hermit/claude.json`) as `{"type": "http", "url": ...}`
5. The runtime workspace override is rewritten, tinyproxy and the server image are built, and `docker compose up -d tinyproxy mcp-*` runs

Set `HERMIT_NO_REBUILD=1` to skip step 5 (used by tests/scripts).

### Workspace consistency for MCP servers

`hermit start` writes `mcp/.runtime/workspace.yml` (git-ignored) via `sync_workspace_override`. It records `x-hermit.workspace_mode`/`workspace_source` and either renames the shared `workspace` volume key (named-volume mode) or replaces the `/home/node/workspace` and each MCP `/data` entry with a bind of the `--mount` path. `compose_cmd` appends it last so it wins the merge; claude-code and every enabled workspace-mounting MCP service therefore resolve to the same source. `mcp add/rm` reuse the currently pinned source (`current_workspace_source`) so a server added mid-session mounts what Claude is using. `hermit mcp sync-workspace [--mount <path>]` regenerates the file without starting Claude (tests use this).

The override also sets `NO_PROXY`/`no_proxy` on claude-code to the enabled `mcp-*` hostnames. Claude must not reach MCP servers through tinyproxy: tinyproxy has no persistent-connection support and, after relaying a streamed SSE response, forwards the client's next keep-alive request as raw proxy-form bytes (HTTP 400 from the server). Single-request access through the proxy (what the probe tests and `^mcp-<name>$` allowlist entries cover) works; Claude's multi-request sessions do not. Registration in claude.json must be `{"type": "http", "url": ...}` — Claude Code skips url-only entries.

MCP servers that need internet access (e.g., `fetch`, `github`) have `HTTP(S)_PROXY` pointed at tinyproxy in their templates, so their own egress goes through the allowlist and is restricted to CONNECT 443 (no direct outbound to other ports).

Compose resolves relative `build:` contexts against the project directory (the first `-f` file's directory, i.e. the repo root), not the template's own directory — so templates must use `./mcp/images/<name>` and `build_mcp_images` passes `--project-directory`.

To add a new MCP server template:
1. Create `mcp/images/<name>/Dockerfile` that installs the server at build time (pinned) and runs `supergateway --stdio "<cmd>" --outputTransport streamableHttp --port <port> --streamableHttpPath /mcp`
2. Create `mcp/templates/<name>.yml` with `build: ./mcp/images/<name>`, `image: ic-mcp-<name>`, and the same hardening flags as the other templates
3. Include required `x-mcp` metadata (`name`, `description`, `transport`, `port`, `path`); parsed with yq via `mcp_meta`. Add `requires_env: VAR` if the server needs a host env var (`mcp add` warns when it is unset)
4. Name the service `mcp-<name>` — the allowlist pattern and registered URL (`http://mcp-<name>:<port><path>`) both assume this
5. Reference the `ic-internal` network (external: true); mount the workspace as `workspace:/data` and declare the `workspace` volume (name ic-workspace, external: true) if the server needs files
6. Users can then enable it with `./hermit mcp add <name>`; the `every shipped MCP template initializes through proxy` test in `tests/mcp.bats` will cover it automatically
