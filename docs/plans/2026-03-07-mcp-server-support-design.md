# MCP Server Support Design

Date: 2026-03-07

## Goal

Add MCP (Model Context Protocol) server support to Isolated Crustacean. MCP servers run as separate Docker containers on the internal network, communicating with Claude Code via streamable HTTP through tinyproxy.

## Architecture

MCP servers are Docker containers connected only to the `internal` network (no internet access). Claude Code reaches them via streamable HTTP URLs routed through tinyproxy. Tinyproxy allowlists each MCP server's hostname, maintaining the existing security model where all traffic is auditable and allowlist-controlled.

```
Claude Code --HTTP_PROXY--> tinyproxy --internal network--> mcp-filesystem:3000
                                      --internal network--> mcp-github:3001
                                      --external network--> api.anthropic.com (internet)
```

## File Structure

```
mcp/
  templates/           # shipped server definitions (version-controlled)
    filesystem.yml
    github.yml
    git.yml
    fetch.yml
    postgres.yml
    sqlite.yml
  enabled/             # active servers (gitignored)
```

## Template Format

Each template is a docker-compose override file with `x-mcp` metadata:

```yaml
x-mcp:
  name: filesystem
  description: "Exposes filesystem access to the workspace volume"
  transport: streamable-http
  port: 3000
  path: /mcp

services:
  mcp-filesystem:
    image: mcp/filesystem:latest
    networks:
      - internal
    volumes:
      - workspace:/data
    environment:
      - MCP_TRANSPORT=streamable-http
      - MCP_PORT=3000
    expose:
      - "3000"

networks:
  internal:
    external: true
```

The `x-mcp` block is ignored by Docker Compose but provides hermit with:
- `name` - used for allowlist entry (`^mcp-<name>$`) and CLI display
- `transport`, `port`, `path` - used to build the Claude Code MCP config URL

## Hermit CLI

New `mcp` subcommand group:

```bash
./hermit mcp list              # list templates and enabled status
./hermit mcp add <name>        # enable a server (auto-rebuilds)
./hermit mcp rm <name>         # disable a server (auto-rebuilds)
./hermit mcp status            # show running MCP server containers
./hermit mcp restart           # restart MCP server containers
```

### What `hermit mcp add <name>` does

1. Copies `mcp/templates/<name>.yml` to `mcp/enabled/<name>.yml`
2. Adds `^mcp-<name>$` to `tinyproxy/allowlist`
3. Merges server entry into `.claude.json` `mcpServers` key using `jq`
4. Runs auto-rebuild (compose build + up)

`hermit mcp rm <name>` reverses each step.

## Compose Integration

All hermit commands that invoke `docker compose` dynamically include enabled MCP overrides:

```bash
docker compose -f docker-compose.yml \
  -f mcp/enabled/filesystem.yml \
  -f mcp/enabled/github.yml \
  up
```

A `compose_files()` helper in hermit scans `mcp/enabled/` and builds the `-f` flags. Every existing compose call uses this helper.

The `internal` network in `docker-compose.yml` must be explicitly named so override files can reference it with `external: true`.

## Claude Code Configuration

MCP servers are configured in `.claude.json` (bind-mounted from host):

```json
{
  "mcpServers": {
    "filesystem": {
      "url": "http://mcp-filesystem:3000/mcp"
    }
  }
}
```

URLs are constructed from `x-mcp` fields: `http://<service-name>:<port><path>`.

Hermit uses `jq` to safely merge the `mcpServers` key without overwriting other `.claude.json` content.

## Testing

- Template validation - each template has valid YAML and required `x-mcp` fields
- Add/rm lifecycle - enabled file, allowlist entry, and `.claude.json` are created/removed correctly
- Allowlist correctness - tinyproxy allows/denies connections after add/rm
- Compose merge - `docker compose config` with overrides produces valid config
- MCP connectivity - Claude Code container can reach enabled MCP servers through tinyproxy

## Doctor Integration

`hermit doctor` gains MCP checks:
- Each enabled server's container is running
- Allowlist entry exists for each enabled server
- `.claude.json` MCP config matches enabled state
- Flag orphaned state (enabled file without allowlist entry or vice versa)

## Initial Templates

Ship templates for: filesystem, github, git, fetch, postgres, sqlite.
