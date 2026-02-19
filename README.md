# Isolated Crustacean

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
docker compose build
```

## Usage

### Start the environment

```bash
docker compose run --rm claude-code
```

This drops you into a bash shell inside the isolated container.

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

### Copy files into the workspace

The workspace is a Docker-managed named volume mounted at `/home/node/workspace`. To get files in:

```bash
# Find the container ID
docker compose ps

# Copy files in
docker cp myfile.txt <container_id>:/home/node/workspace/
```

Or use a bind mount instead by editing `docker-compose.yml`.

## Allowlist Customization

Edit `tinyproxy/allowlist` to add or remove domains. Each line is an anchored ERE regex pattern. After editing, rebuild:

```bash
docker compose build tinyproxy
```

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

## Verify Isolation

```bash
# Should FAIL - no direct internet from claude-code container
docker compose run --rm claude-code -c "curl -s --max-time 5 https://google.com"

# Should be REJECTED by proxy (403)
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://google.com"

# Should SUCCEED - allowed domain
docker compose run --rm claude-code -c "curl -x http://tinyproxy:8888 https://api.anthropic.com"

# Check proxy logs
docker compose logs tinyproxy
```

## Security Properties

- Claude Code has zero direct internet access (enforced at Docker network layer)
- Tinyproxy cannot read API keys or conversation content (no TLS interception)
- Docker socket is never mounted (prevents container escape)
- OAuth credentials stored in a Docker volume, never on the host filesystem
- Allowlist uses anchored regex to prevent subdomain spoofing
