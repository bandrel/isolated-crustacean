# Isolated Crustacean

```
    +============================+
    |  ////  ////  ////  ////    |
    |============================|
    |  _,,_         _,,_         |
    | (o  o)  \./  (o  o)        |
    |  \_/  --( )-- \_/          |
    | /|||\ / | \ /|||\          |
    |============================|
    |  ////  ////  ////  ////    |
    +============================+
      ISOLATED CRUSTACEAN
      Network-isolated Claude Code
```

Run Claude Code inside a network-isolated Docker container where all internet traffic is forced through a tinyproxy allowlist proxy. This prevents Claude Code from reaching any domain not explicitly permitted.

## Architecture

```
[claude-code container]          [tinyproxy container]
  - node:24-bookworm-slim          - alpine:3.22
  - claude-code CLI                - forward proxy
  - HTTP(S)_PROXY env set          - allowlist filtering
  - ENFORCED: no internet route    - domain allowlist
        |                                |          |
        +--- internal network (no gw) ---+          |
                                         +--- external network --- internet
```

The `internal` network is marked `internal: true` — it has no default gateway, so claude-code has no route to the internet regardless of proxy environment variables. Network isolation is the enforcement boundary; proxy env vars are a defense-in-depth layer.

Two other services run on the internal network:
- **probe** (debian:bookworm-slim) - isolation verification test harness, runs in profile "probe"
- **MCP servers** - pluggable Model Context Protocol servers (filesystem, git, fetch, sqlite, github)

The `external` network is a standard bridge with internet access; only tinyproxy connects to it. Tinyproxy bridges both networks and enforces the domain allowlist.

## Prerequisites

- Docker (with `docker compose`)
- `jq` — used by `hermit` to edit `$HERMIT_CONFIG_DIR/claude.json` (default `~/.hermit/claude.json`)
- `yq` — required by every `hermit` command except `help`; it parses MCP template metadata and the runtime workspace override (`hermit` exits with `Error: yq is required` if it is missing)
- `bats-core` — required only for `./hermit test`

On macOS: `brew install jq yq bats-core`.

## Setup

```bash
./hermit build
```

### Authentication

Claude Code configuration is stored in an isolated container directory (`/home/node/.claude`), saved on the host at `$HERMIT_CONFIG_DIR/claude` (default: `~/.hermit/claude`) — **not** shared with your host's `~/.claude` — which prevents a compromised container from modifying your host configuration.

You have three options to authenticate:

**Option 1: Log in inside the container (recommended)**

```bash
./hermit start
# Inside Claude:
/login
```

This opens an OAuth URL to authenticate. Your credentials are stored on the host at `$HERMIT_CONFIG_DIR/claude` (default `~/.hermit/claude`), mounted into the container at `/home/node/.claude`, and persisted across sessions.

**Option 2: Use a token from the host**

On your host machine, generate a setup token:

```bash
claude setup-token
```

Then pass it to the container before starting:

```bash
CLAUDE_CODE_OAUTH_TOKEN=$(claude setup-token) ./hermit start
```

**Option 3: Use an API key**

If you have an Anthropic API key, export it before starting:

```bash
ANTHROPIC_API_KEY=sk-ant-... ./hermit start
```

The container receives the token or key but **cannot access** your host's `~/.claude` directory — it has its own isolated configuration.

### Upgrading from an earlier version

Earlier versions bind-mounted your host `~/.claude` and `~/.claude.json` into the container. If you are upgrading, three things change:

1. **Authentication is no longer shared with the host.** The container now uses `$HERMIT_CONFIG_DIR` (default `~/.hermit/`), which starts empty. Run `/login` once inside `./hermit start`, or export `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` as described above. On Linux hosts you can alternatively copy an existing credentials file: `cp ~/.claude/.credentials.json ~/.hermit/claude/`. On macOS there is no file to copy — Claude Code keeps credentials in the Keychain — so use `/login` or a token.

2. **Old `hermit mcp add` wrote `mcpServers` entries into your host `~/.claude.json`.** Those entries (`http://mcp-<name>:<port>/mcp`) are unreachable from the host and should be removed. This drops every server whose URL starts with `http://mcp-` and leaves everything else untouched (back the file up first):

   ```bash
   cp ~/.claude.json ~/.claude.json.bak
   jq 'if .mcpServers then del(.mcpServers[] | select(.url? // "" | test("^http://mcp-"))) else . end' \
     ~/.claude.json > ~/.claude.json.tmp && mv ~/.claude.json.tmp ~/.claude.json
   ```

3. **Workspaces created under the old `isolated-crustaion-<name>` prefix keep working.** `hermit workspace list/switch/rm` fall back to the legacy prefix when no `isolated-crustacean-<name>` volume exists, so nothing needs renaming.

## Usage

### Start Claude

```bash
./hermit start
```

This launches Claude Code in the isolated container.

To drop into a bash shell instead:

```bash
./hermit shell
```

### MCP Server Support

Enable Claude with access to MCP (Model Context Protocol) servers running inside the isolated network:

```bash
# List available server templates and their status
./hermit mcp list

# Enable an MCP server
./hermit mcp add filesystem

# Disable an MCP server
./hermit mcp rm filesystem
```

When you add a server, hermit automatically:
- Copies the server template to `mcp/enabled/`
- Adds the server's internal hostname to the proxy allowlist and rebuilds tinyproxy
- Configures the server in `$HERMIT_CONFIG_DIR/claude.json` (default `~/.hermit/claude.json`)
- Builds the server image and starts it on the isolated network

Available MCP server templates (see `mcp/templates/`):

| Template | What it is | Notes |
|---|---|---|
| `filesystem` | Upstream reference server (`@modelcontextprotocol/server-filesystem`) | Serves the workspace at `/data` |
| `git` | Upstream reference server (`mcp-server-git`) | Tools take `repo_path`, e.g. `/data/myproject` |
| `fetch` | Upstream reference server (`mcp-server-fetch`) | Fetches go through tinyproxy, so only allowlisted HTTPS hosts work |
| `sqlite` | Reference server (`mcp-server-sqlite`) | Database at `/data/sqlite.db`; pinned to a stable SDK version |
| `github` | Official `ghcr.io/github/github-mcp-server` binary | Export `GITHUB_PERSONAL_ACCESS_TOKEN` before `mcp add`/`start`; tool calls fail without it |

The upstream servers only speak stdio, so each template builds a local image
(`mcp/images/<name>/Dockerfile`) that installs the pinned server package at
build time and wraps it with [supergateway](https://github.com/supercorp-ai/supergateway)
as a stdio→Streamable-HTTP bridge. Runtime containers have no internet
access, so nothing is downloaded when they start.

MCP servers that mount the workspace at `/data` always see the same files as
Claude Code. `hermit start` writes `mcp/.runtime/workspace.yml` (git-ignored)
pinning the active named workspace, or the `--mount` path, for claude-code
and every enabled MCP service, then (re)creates the MCP containers before
launching Claude. `hermit mcp sync-workspace [--mount <path>]` regenerates
that file on demand.

That same file sets `NO_PROXY` on claude-code to the enabled `mcp-*`
hostnames, so Claude talks to MCP servers directly over the isolated
`ic-internal` network rather than through tinyproxy. tinyproxy does not
support persistent client connections: after relaying a streamed (SSE)
MCP response it forwards the client's next keep-alive request verbatim,
which the server rejects with HTTP 400. Bypassing the proxy for these
internal names does not widen egress; the container has no route to the
internet either way.

- `./hermit start` launches Claude Code directly (interactive TUI). Use `/resume` inside Claude to pick up a previous conversation.
- For one-shot, non-interactive use: `./hermit exec claude --print "Explain this codebase"`
- For a bash shell in the container: `./hermit shell` (then run `claude` or `claude --print "..."` from there).

### Run commands in the container

```bash
# Run a one-off command
./hermit exec echo hello

# Drop into an interactive bash shell
./hermit shell
```

### Hermit commands reference

```bash
# Environment and containers
./hermit build       # Build all containers
./hermit rebuild     # Rebuild and restart (e.g. after allowlist changes)
./hermit start       # Start interactive Claude Code session (--mount <path>)
./hermit stop        # Stop all running containers
./hermit status      # Show container status
./hermit exec <cmd>  # Run a command in the Claude Code container
./hermit shell       # Start interactive bash in the Claude Code container

# Diagnostics
./hermit logs        # Show tinyproxy logs (--blocked: show only denied requests)
./hermit logs -f     # Follow logs in real-time
./hermit doctor      # Run health diagnostics (proxy, DNS, connectivity)
./hermit test        # Run isolation verification tests

# Allowlist management
./hermit allowlist list                  # List current allowlist entries
./hermit allowlist add example.com       # Add exact-match domain
./hermit allowlist add --subdomains example.com  # Add domain plus subdomains
./hermit allowlist remove example.com    # Remove domain entries
./hermit allowlist check example.com     # Check if domain would be allowed

# Allowlist profiles
./hermit allowlist profile save <name>   # Save current allowlist as profile
./hermit allowlist profile load <name>   # Load a saved profile
./hermit allowlist profile list          # List saved profiles
./hermit allowlist profile rm <name>     # Delete a profile

# Workspace management
./hermit workspace list                  # List all workspaces
./hermit workspace create <name>         # Create a new workspace
./hermit workspace switch <name>         # Switch active workspace
./hermit workspace current               # Show the currently active workspace
./hermit workspace rm <name>             # Remove a workspace

# MCP server management
./hermit mcp list                        # List available servers and status
./hermit mcp add <server>                # Enable an MCP server from template
./hermit mcp rm <server>                 # Disable an MCP server
./hermit mcp sync-workspace [--mount]    # Regenerate workspace override without starting
./hermit mcp status                      # Show running MCP server containers
./hermit mcp restart                     # Restart MCP server containers
```

### Bind-mount a host directory

```bash
./hermit start --mount /path/to/project
```

This mounts the host directory at `/home/node/workspace` inside the container instead of using the default Docker volume. The mount is read-write. `hermit` refuses to mount its own checkout or any directory containing it (see [What It Does NOT Guarantee](#what-it-does-not-guarantee)).

### Copy files into the workspace

The workspace is a Docker-managed named volume mounted at `/home/node/workspace` (the container runs as the `node` user). To get files in:

```bash
# Find the container ID
docker compose ps

# Copy files in
docker cp myfile.txt <container_id>:/home/node/workspace/
```

## Allowlist Customization

Use `./hermit allowlist` to manage allowed domains without editing regex by hand:

```bash
# List current entries with line numbers
./hermit allowlist list

# Add a domain (exact match: ^example\.com$)
./hermit allowlist add example.com

# Add a domain plus all its subdomains (^(.+\.)?example\.com$)
./hermit allowlist add --subdomains example.com

# Remove all entries for a domain
./hermit allowlist remove example.com

# Check whether a domain would be allowed
./hermit allowlist check api.anthropic.com   # exits 0 (allowed)
./hermit allowlist check evil.com            # exits 1 (blocked)
```

After adding or removing entries, rebuild to apply the changes:

```bash
./hermit rebuild
```

### Allowlist profiles

Save and load named allowlist configurations:

```bash
# Save current allowlist as a profile
./hermit allowlist profile save strict

# List saved profiles
./hermit allowlist profile list

# Load a saved profile
./hermit allowlist profile load strict

# Delete a profile
./hermit allowlist profile rm strict
```

You can also edit `tinyproxy/allowlist` directly. Each line is an anchored ERE regex pattern.

Default allowed domains:

| Domain | Purpose |
|--------|---------|
| `api.anthropic.com` | Claude API (required) |
| `console.anthropic.com` | Console OAuth |
| `platform.claude.com` | Console auth |
| `claude.ai` | claude.ai OAuth |
| `registry.npmjs.org` | npm packages |
| `github.com`, `*.github.com` | Git operations |
| `*.githubusercontent.com` | GitHub raw content |

Note: Claude Code disables nonessential traffic with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, which suppresses requests for feature flags and error reporting.

## Threat Model

### What Isolation Guarantees

- **No direct egress**: Claude Code container has zero direct route to the internet. It can only reach external hosts via tinyproxy.
- **Allowlist enforcement**: Only domains matching regex patterns in `tinyproxy/allowlist` are reachable. All others are rejected with HTTP 403.
- **No DNS leakage**: The internal network has no default gateway, and Docker's embedded DNS on an `internal: true` network does not forward external lookups on current Docker Engine versions, so external hostnames do not resolve there; only `mcp-*` internal services and tinyproxy itself are reachable by name. This is verified by `./hermit test` (`external DNS does not resolve on internal network` in `tests/isolation.bats`) rather than assumed — run it after upgrading Docker.
- **No TLS interception**: Tinyproxy is an explicit forward proxy, not a man-in-the-middle. It cannot read, intercept, or modify API keys, conversation content, or any other TLS-encrypted data.
- **Isolated configuration**: Container configuration is stored in `$HERMIT_CONFIG_DIR` on the host (default `~/.hermit/`), not mounted from your host's `~/.claude`, so a compromised container cannot modify your host config. Auth credentials persist in this mounted directory across sessions.

### What It Does NOT Guarantee

- **Exfiltration via allowlisted services**: User-controlled data can still be exfiltrated to any allowlisted service that accepts uploads or arbitrary content. Examples:
  - **api.anthropic.com**: Another Claude Code instance or client calling the API with a different key
  - **github.com**: Pushing code to a repo, creating gists, opening issues
  - **registry.npmjs.org**: Publishing packages
  - **`fetch` MCP server** (if enabled): another HTTP client that reaches allowlisted hosts via tinyproxy. It adds no new destinations, so the bound is the same, but it is one more way to send data to them.
- **Allowlist as destination boundary, not data boundary**: The allowlist restricts *where* the container can connect, not *what data* it can send. A malicious prompt injection or supply chain attack could exfiltrate credentials or conversation content to any of these services.
- **`--mount` directories are fully writable**: Everything under `./hermit start --mount <path>` is read-write from the container. Never mount this repository or a directory containing it — a compromised container could rewrite `hermit`, the compose files, the allowlist, or `mcp/enabled/` and gain code execution on the host the next time you run `./hermit`. `hermit` refuses these paths, but it cannot recognise other sensitive directories (your home directory, dotfiles, other tools' checkouts); mount only the project you intend Claude to edit.

### How to Tighten This

- Remove GitHub and npm entries from `tinyproxy/allowlist` if you don't need them:
  ```bash
  ./hermit allowlist remove github.com
  ./hermit allowlist remove registry.npmjs.org
  ./hermit rebuild
  ```
  Note: `remove github.com` removes github.com entries but leaves `githubusercontent.com`, which is often needed for GitHub raw content. Remove that separately if desired.
- Use allowlist profiles to switch between strict and permissive configurations:
  ```bash
  ./hermit allowlist profile save strict
  ./hermit allowlist profile load strict
  ```

### Residual Risk

- **Docker escape**: If the container itself is compromised and a Docker escape is possible, the allowlist provides no protection. This is a general Docker limitation, not specific to Isolated Crustacean.

## Health Check

Run diagnostics to verify proxy, DNS, and connectivity:

```bash
./hermit doctor
```

## Logs

```bash
# Show all tinyproxy logs
./hermit logs

# Follow logs
./hermit logs -f

# Show only denied/blocked requests
./hermit logs --blocked
```

## Verify Isolation

Run all isolation verification checks at once:

```bash
./hermit test
```

Run specific health diagnostics:

```bash
./hermit doctor
```

To manually verify isolation using the probe container (which has curl and dnsutils):

```bash
export HERMIT_CONFIG_DIR="${HERMIT_CONFIG_DIR:-$HOME/.hermit}"

# Should FAIL - no internet from internal network (DNS resolve error)
docker compose --profile probe run --rm --no-deps -T --entrypoint bash \
  -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= \
  probe -c "curl -sS --max-time 5 https://example.com 2>&1"
# Output: curl: (6) Could not resolve host: example.com

# Should be REJECTED by proxy (HTTP 403)
docker compose --profile probe run --rm --no-deps -T --entrypoint bash \
  -e HTTP_PROXY=http://tinyproxy:8888 -e HTTPS_PROXY=http://tinyproxy:8888 \
  -e http_proxy=http://tinyproxy:8888 -e https_proxy=http://tinyproxy:8888 \
  probe -c "curl -s -o /dev/null -w '%{http_connect}\n' https://evil.com"
# Output: 403

# Should SUCCEED - allowed domain via proxy (HTTP status code, not 000)
docker compose --profile probe run --rm --no-deps -T --entrypoint bash \
  -e HTTP_PROXY=http://tinyproxy:8888 -e HTTPS_PROXY=http://tinyproxy:8888 \
  -e http_proxy=http://tinyproxy:8888 -e https_proxy=http://tinyproxy:8888 \
  probe -c "curl -s -o /dev/null -w '%{http_code}\n' https://api.anthropic.com"
# Output: 404 (or other HTTP status, not 000)
```

## Security Properties

- Claude Code has zero direct internet access (enforced at Docker network layer)
- Tinyproxy cannot read API keys or conversation content (no TLS interception)
- Docker socket is never mounted (prevents container escape)
- Container configuration is isolated from the host — stored in `$HERMIT_CONFIG_DIR` on the host (default `~/.hermit/`), not your `~/.claude`, preventing a compromised container from modifying your host config
- OAuth credentials from `/login` persist in `$HERMIT_CONFIG_DIR/claude` (mounted at /home/node/.claude) across sessions; `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` are passed through from the host environment only when explicitly set
- Works on both macOS and Linux hosts
- Allowlist uses anchored regex to prevent subdomain spoofing
