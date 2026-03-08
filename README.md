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
  - node:20-slim                   - alpine:3.21
  - claude-code CLI                - tinyproxy
  - HTTP(S)_PROXY set              - allowlist filtering
  - NO direct internet             - domain allowlist
        |                                |          |
        +--- internal network (no gw) ---+          |
                                         +--- external network --- internet
```

- **internal network** (`internal: true`) - no default gateway, so claude-code cannot route to the internet
- **external network** - standard bridge with internet access, only tinyproxy connects to it
- **tinyproxy** bridges both networks, enforcing a domain allowlist before proxying

## Setup

```bash
./hermit build
```

## Usage

### Start the environment

```bash
./hermit start
```

This drops you into a bash shell inside the isolated container.

### MCP Server Support

Enable Claude with access to MCP (Model Context Protocol) servers running inside the isolated network:

```bash
# List available server templates
ls mcp/templates/

# Enable an MCP server
./hermit mcp add filesystem

# Disable an MCP server
./hermit mcp rm filesystem
```

When you add a server, hermit automatically:
- Copies the server template to `mcp/enabled/`
- Adds the server's internal hostname to the proxy allowlist
- Configures the server in `~/.claude.json` under `mcpServers`

Available MCP server templates (see `mcp/templates/` for full list):

- `filesystem` - read/write access to the shared workspace volume

### First run - log in

On first use (or when credentials expire), authenticate with OAuth:

```bash
claude --login
```

This prints a URL - open it in a browser on your host machine to complete the OAuth flow. Credentials are stored in a persistent Docker volume (`claude-config`) so you only need to do this once.

### Start Claude

```bash
claude
```

Or run a one-off command:

```bash
claude --print "Explain this codebase"
```

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
./hermit workspace rm <name>             # Remove a workspace

# MCP server management
./hermit mcp add <server>                # Enable an MCP server from template
./hermit mcp rm <server>                 # Disable an MCP server
```

### Bind-mount a host directory

```bash
./hermit start --mount /path/to/project
```

This mounts the host directory at `/home/node/workspace` inside the container instead of using the default Docker volume.

### Copy files into the workspace

The workspace is a Docker-managed named volume mounted at `/home/<username>/workspace` (matching your host username). To get files in:

```bash
# Find the container ID
docker compose ps

# Copy files in
docker cp myfile.txt <container_id>:/home/$(whoami)/workspace/
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
| `statsig.anthropic.com` | Feature flags |
| `statsig.com` | Feature flags |
| `*.sentry.io` | Error reporting |
| `registry.npmjs.org` | npm packages |
| `github.com`, `*.github.com` | Git operations |
| `*.githubusercontent.com` | GitHub raw content |

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

Or run individual checks manually:

```bash
# Should FAIL - no direct internet from claude-code container
docker compose run --rm claude-code -c "curl -s --max-time 5 https://google.com"

# Should be REJECTED by proxy (403)
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://google.com"

# Should SUCCEED - allowed domain
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://api.anthropic.com"

# Check proxy logs
./hermit logs
```

## Security Properties

- Claude Code has zero direct internet access (enforced at Docker network layer)
- Tinyproxy cannot read API keys or conversation content (no TLS interception)
- Docker socket is never mounted (prevents container escape)
- Both `~/.claude/` and `~/.claude.json` are bind-mounted from the host (using absolute `HOST_HOME` path for cross-platform reliability)
- Works on both macOS and Linux hosts
- Allowlist uses anchored regex to prevent subdomain spoofing
