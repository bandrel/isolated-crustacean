# MCP Server Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add MCP server support so Claude Code can use MCP servers running as Docker containers on the internal network, communicating via streamable HTTP through tinyproxy.

**Architecture:** MCP servers are compose override files activated by `hermit mcp add`. Each server gets its own container on the `internal` network. Claude Code reaches them via HTTP through tinyproxy, which allowlists each server's hostname. A `compose_files()` helper in hermit dynamically includes all enabled overrides in every compose call.

**Tech Stack:** Bash (hermit CLI), Docker Compose override files, jq (JSON manipulation), bats-core (testing), YAML with x- extension fields

---

### Task 1: Name the internal network explicitly

The `internal` network in `docker-compose.yml` uses compose's auto-generated name (e.g., `isolated-crustacean_internal`). Override files need to reference it with `external: true`, which requires a stable, explicit name.

**Files:**
- Modify: `docker-compose.yml:26-29`

**Step 1: Write the failing test**

Create `tests/mcp.bats` with a test that validates named network:

```bash
#!/usr/bin/env bats

load test_helper

@test "internal network has explicit name" {
    run docker compose -f "$COMPOSE_PROJECT_DIR/docker-compose.yml" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: ic-internal"* ]]
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/mcp.bats`
Expected: FAIL - the network doesn't have `name: ic-internal`

**Step 3: Add explicit network name**

In `docker-compose.yml`, change the `internal` network block:

```yaml
networks:
  internal:
    name: ic-internal
    internal: true
  external:
    name: ic-external
    driver: bridge
```

Also name `external` for consistency. Name the workspace volume too:

```yaml
volumes:
  workspace:
    name: ic-workspace
```

**Step 4: Run test to verify it passes**

Run: `bats tests/mcp.bats`
Expected: PASS

**Step 5: Commit**

```bash
git add docker-compose.yml tests/mcp.bats
git commit -m "feat(mcp): name networks explicitly for compose overrides"
```

---

### Task 2: Create directory structure and .gitignore

**Files:**
- Create: `mcp/templates/.gitkeep`
- Create: `mcp/enabled/.gitkeep`
- Modify: `.gitignore`

**Step 1: Create directories**

```bash
mkdir -p mcp/templates mcp/enabled
touch mcp/templates/.gitkeep mcp/enabled/.gitkeep
```

**Step 2: Update .gitignore**

Add `mcp/enabled/` (but not the .gitkeep) to `.gitignore`. Current contents:

```
.claude/
.env
.hermit-workspace
```

Append:

```
mcp/enabled/*
!mcp/enabled/.gitkeep
```

**Step 3: Commit**

```bash
git add .gitignore mcp/
git commit -m "feat(mcp): add template and enabled directory structure"
```

---

### Task 3: Add `compose_files()` helper to hermit

This helper scans `mcp/enabled/` and builds `-f` flags for every `docker compose` call. Every existing compose call in hermit must use it.

**Files:**
- Modify: `hermit:1-10` (add helper function)
- Modify: `hermit` (all `docker compose` calls)
- Modify: `tests/test_helper.bash` (update compose calls)

**Step 1: Write the failing test**

Add to `tests/mcp.bats`:

```bash
@test "compose_files helper includes base compose file" {
    source "$HERMIT" --source-only 2>/dev/null || true
    run bash -c "source '$COMPOSE_PROJECT_DIR/hermit' --source-only 2>/dev/null; compose_files"
    [[ "$output" == *"-f"*"docker-compose.yml"* ]]
}
```

Actually, sourcing hermit is tricky since it runs commands immediately. Instead, test indirectly: verify `hermit status` works with no MCP servers enabled (baseline).

```bash
@test "hermit status works with no MCP servers enabled" {
    run "$HERMIT" status
    [ "$status" -eq 0 ]
}
```

**Step 2: Run test to verify it passes (baseline)**

Run: `bats tests/mcp.bats`
Expected: PASS (this is a baseline - we'll break and fix)

**Step 3: Add compose_files() helper**

Add this function near the top of `hermit`, after the `cd "$SCRIPT_DIR"` line:

```bash
compose_cmd() {
    local -a files=(-f "$SCRIPT_DIR/docker-compose.yml")
    for f in "$SCRIPT_DIR"/mcp/enabled/*.yml; do
        [[ -e "$f" ]] && files+=(-f "$f")
    done
    docker compose "${files[@]}" "$@"
}
```

**Step 4: Replace all `docker compose` calls with `compose_cmd`**

In hermit, replace every `docker compose` invocation with `compose_cmd`. The calls are at these locations:
- `hermit:86` - `docker compose run --rm ... claude-code` (start)
- `hermit:89` - `docker compose build` (build)
- `hermit:92-93` - `docker compose build` + `docker compose up -d tinyproxy` (rebuild)
- `hermit:107-109` - `docker compose logs` (logs)
- `hermit:117` - `docker compose up -d tinyproxy` (test)
- `hermit:118` - bats (unchanged, but test_helper needs updating)
- `hermit:121` - `docker compose down` (stop)
- `hermit:124` - `docker compose ps` (status)
- `hermit:278` - `docker compose run --rm --no-deps -T` (exec)
- `hermit:281` - `docker compose run --rm --no-deps` (shell)
- `hermit:288,297,307,318` - `docker compose` calls in doctor

Also update `tests/test_helper.bash` to use the same pattern:

```bash
COMPOSE_FILES=(-f "$COMPOSE_PROJECT_DIR/docker-compose.yml")
for f in "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml; do
    [[ -e "$f" ]] && COMPOSE_FILES+=(-f "$f")
done

run_in_container() {
    docker compose "${COMPOSE_FILES[@]}" \
        run --rm --no-deps -T --entrypoint bash claude-code -c "$1" 2>/dev/null
}

run_in_container_no_proxy() {
    docker compose "${COMPOSE_FILES[@]}" \
        run --rm --no-deps -T --entrypoint bash \
        -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= \
        claude-code -c "$1" 2>/dev/null
}
```

**Step 5: Run all existing tests to verify nothing broke**

Run: `bats tests/`
Expected: All existing tests still pass

**Step 6: Commit**

```bash
git add hermit tests/test_helper.bash tests/mcp.bats
git commit -m "feat(mcp): add compose_cmd helper for dynamic override inclusion"
```

---

### Task 4: Create initial MCP server templates

Create 6 templates. Each is a docker-compose override with `x-mcp` metadata. Use real MCP server images from the `mcp/` Docker Hub namespace where they exist. For servers without official images, use `ghcr.io/modelcontextprotocol/<name>-mcp-server:latest` as the convention.

**Important:** MCP servers use streamable HTTP transport. The `x-mcp` metadata tells hermit how to build the URL for `.claude.json`. Each service name MUST be `mcp-<name>` to match the allowlist pattern `^mcp-<name>$`.

**Files:**
- Create: `mcp/templates/filesystem.yml`
- Create: `mcp/templates/github.yml`
- Create: `mcp/templates/git.yml`
- Create: `mcp/templates/fetch.yml`
- Create: `mcp/templates/postgres.yml`
- Create: `mcp/templates/sqlite.yml`

**Step 1: Write template validation test**

Add to `tests/mcp.bats`:

```bash
@test "all templates have required x-mcp fields" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        for field in name description transport port path; do
            run grep "  $field:" "$tmpl"
            [ "$status" -eq 0 ] || {
                echo "Missing x-mcp.$field in $(basename "$tmpl")"
                return 1
            }
        done
    done
}

@test "all templates define a service named mcp-<name>" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        name=$(grep '  name:' "$tmpl" | head -1 | awk '{print $2}')
        run grep "  mcp-${name}:" "$tmpl"
        [ "$status" -eq 0 ] || {
            echo "Service mcp-${name} not found in $(basename "$tmpl")"
            return 1
        }
    done
}

@test "all templates reference the ic-internal network" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        run grep -A1 "^networks:" "$tmpl"
        [ "$status" -eq 0 ]
        [[ "$output" == *"name: ic-internal"* ]]
    done
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/mcp.bats`
Expected: FAIL - no templates exist yet

**Step 3: Create filesystem.yml**

```yaml
x-mcp:
  name: filesystem
  description: "Read/write access to the shared workspace volume"
  transport: streamable-http
  port: 3000
  path: /mcp

services:
  mcp-filesystem:
    image: mcp/filesystem-server:latest
    networks:
      - internal
    volumes:
      - workspace:/data
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3000"
    expose:
      - "3000"

networks:
  internal:
    name: ic-internal
    external: true

volumes:
  workspace:
    name: ic-workspace
    external: true
```

**Step 4: Create github.yml**

```yaml
x-mcp:
  name: github
  description: "GitHub API access (repos, issues, PRs)"
  transport: streamable-http
  port: 3001
  path: /mcp

services:
  mcp-github:
    image: mcp/github-server:latest
    networks:
      - internal
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3001"
      GITHUB_TOKEN: "${GITHUB_TOKEN:-}"
    expose:
      - "3001"

networks:
  internal:
    name: ic-internal
    external: true
```

**Step 5: Create git.yml**

```yaml
x-mcp:
  name: git
  description: "Local git operations on the workspace"
  transport: streamable-http
  port: 3002
  path: /mcp

services:
  mcp-git:
    image: mcp/git-server:latest
    networks:
      - internal
    volumes:
      - workspace:/data
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3002"
    expose:
      - "3002"

networks:
  internal:
    name: ic-internal
    external: true

volumes:
  workspace:
    name: ic-workspace
    external: true
```

**Step 6: Create fetch.yml**

```yaml
x-mcp:
  name: fetch
  description: "HTTP fetch - requests route through tinyproxy"
  transport: streamable-http
  port: 3003
  path: /mcp

services:
  mcp-fetch:
    image: mcp/fetch-server:latest
    networks:
      - internal
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3003"
      HTTP_PROXY: http://tinyproxy:8888
      HTTPS_PROXY: http://tinyproxy:8888
    expose:
      - "3003"

networks:
  internal:
    name: ic-internal
    external: true
```

**Step 7: Create postgres.yml**

```yaml
x-mcp:
  name: postgres
  description: "PostgreSQL database access"
  transport: streamable-http
  port: 3004
  path: /mcp

services:
  mcp-postgres:
    image: mcp/postgres-server:latest
    networks:
      - internal
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3004"
      POSTGRES_CONNECTION_STRING: "${POSTGRES_CONNECTION_STRING:-}"
    expose:
      - "3004"

networks:
  internal:
    name: ic-internal
    external: true
```

**Step 8: Create sqlite.yml**

```yaml
x-mcp:
  name: sqlite
  description: "SQLite database access on the workspace volume"
  transport: streamable-http
  port: 3005
  path: /mcp

services:
  mcp-sqlite:
    image: mcp/sqlite-server:latest
    networks:
      - internal
    volumes:
      - workspace:/data
    environment:
      MCP_TRANSPORT: streamable-http
      MCP_PORT: "3005"
    expose:
      - "3005"

networks:
  internal:
    name: ic-internal
    external: true

volumes:
  workspace:
    name: ic-workspace
    external: true
```

**Step 9: Run tests**

Run: `bats tests/mcp.bats`
Expected: PASS

**Step 10: Commit**

```bash
git add mcp/templates/
git commit -m "feat(mcp): add initial server templates"
```

---

### Task 5: Implement `hermit mcp add`

The core command: copies template to enabled, adds allowlist entry, updates `.claude.json`, auto-rebuilds.

**Files:**
- Modify: `hermit` (add `mcp` case block)

**Step 1: Write the failing test**

Add to `tests/mcp.bats`:

```bash
setup() {
    # Back up allowlist and .claude.json before each test
    cp "$ALLOWLIST_FILE" "$ALLOWLIST_FILE.bak"
    if [[ -f "$HOME/.claude.json" ]]; then
        cp "$HOME/.claude.json" "$HOME/.claude.json.bak"
    fi
}

teardown() {
    # Restore originals after each test
    mv "$ALLOWLIST_FILE.bak" "$ALLOWLIST_FILE"
    if [[ -f "$HOME/.claude.json.bak" ]]; then
        mv "$HOME/.claude.json.bak" "$HOME/.claude.json"
    fi
    # Clean up enabled
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml
}

@test "mcp add copies template to enabled" {
    run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [ -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}

@test "mcp add adds allowlist entry" {
    run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    grep -q '^\^mcp-filesystem\$$' "$ALLOWLIST_FILE"
}

@test "mcp add updates claude.json mcpServers" {
    run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers.filesystem.url' "$HOME/.claude.json"
    [ "$output" = "http://mcp-filesystem:3000/mcp" ]
}

@test "mcp add fails for nonexistent template" {
    run "$HERMIT" mcp add nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "mcp add warns on duplicate" {
    "$HERMIT" mcp add filesystem
    run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/mcp.bats`
Expected: FAIL - `mcp` subcommand doesn't exist

**Step 3: Implement `hermit mcp add`**

Add a new `mcp)` case block in hermit's main `case` statement (before the `*)` catch-all). Also add `mcp` to the `usage()` output.

Key implementation details:
- Read `x-mcp` fields from the template using `grep` + `awk` (avoid requiring a YAML parser - hermit only has standard unix tools + jq)
- Build the allowlist pattern as `^mcp-<name>$`
- Build the MCP URL as `http://mcp-<name>:<port><path>`
- Use `jq` to merge into `.claude.json`: `jq '.mcpServers.<name> = {"url": "<url>"}' "$HOME/.claude.json"`
- The auto-rebuild calls `compose_cmd build` then `compose_cmd up -d`

```bash
mcp)
    shift
    _mcp_subcmd="${1:-}"
    case "$_mcp_subcmd" in
        add)
            shift
            _mcp_name="${1:-}"
            if [[ -z "$_mcp_name" ]]; then
                echo "Error: 'mcp add' requires a server name" >&2
                exit 1
            fi
            _tmpl="$SCRIPT_DIR/mcp/templates/${_mcp_name}.yml"
            if [[ ! -f "$_tmpl" ]]; then
                echo "Error: template '$_mcp_name' not found in mcp/templates/" >&2
                exit 1
            fi
            _enabled="$SCRIPT_DIR/mcp/enabled/${_mcp_name}.yml"
            if [[ -f "$_enabled" ]]; then
                echo "MCP server '$_mcp_name' is already enabled"
                exit 0
            fi
            # Read x-mcp fields
            _mcp_port=$(grep '  port:' "$_tmpl" | head -1 | awk '{print $2}')
            _mcp_path=$(grep '  path:' "$_tmpl" | head -1 | awk '{print $2}')
            _mcp_url="http://mcp-${_mcp_name}:${_mcp_port}${_mcp_path}"
            # Copy template
            cp "$_tmpl" "$_enabled"
            # Add allowlist entry
            _al_pattern="^mcp-${_mcp_name}$"
            if ! grep -qF "$_al_pattern" "$SCRIPT_DIR/tinyproxy/allowlist"; then
                echo "$_al_pattern" >> "$SCRIPT_DIR/tinyproxy/allowlist"
            fi
            # Update .claude.json
            _claude_json="$HOME/.claude.json"
            if [[ ! -s "$_claude_json" ]]; then
                echo '{}' > "$_claude_json"
            fi
            _tmp_json="$(mktemp)"
            jq --arg name "$_mcp_name" --arg url "$_mcp_url" \
                '.mcpServers[$name] = {"url": $url}' "$_claude_json" > "$_tmp_json"
            mv "$_tmp_json" "$_claude_json"
            echo "Enabled MCP server: $_mcp_name ($_mcp_url)"
            # Auto-rebuild
            compose_cmd build
            compose_cmd up -d
            ;;
```

**Step 4: Run tests**

Run: `bats tests/mcp.bats`
Expected: PASS (add tests pass; the auto-rebuild may fail without real images, but the file/allowlist/json tests should pass). Note: you may need to skip the auto-rebuild in test mode or mock it. Add `--no-rebuild` flag or set `HERMIT_NO_REBUILD=1` env var for testing:

```bash
# At end of mcp add, replace the rebuild lines:
if [[ "${HERMIT_NO_REBUILD:-}" != "1" ]]; then
    compose_cmd build
    compose_cmd up -d
fi
```

Update tests to set `HERMIT_NO_REBUILD=1`:

```bash
@test "mcp add copies template to enabled" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [ -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}
```

**Step 5: Commit**

```bash
git add hermit tests/mcp.bats
git commit -m "feat(mcp): implement hermit mcp add"
```

---

### Task 6: Implement `hermit mcp rm`

Reverse of add: removes enabled file, allowlist entry, `.claude.json` entry, auto-rebuilds.

**Files:**
- Modify: `hermit` (add `rm` to `mcp` case)
- Modify: `tests/mcp.bats`

**Step 1: Write the failing test**

```bash
@test "mcp rm removes enabled file" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    [ ! -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}

@test "mcp rm removes allowlist entry" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    ! grep -q '^\^mcp-filesystem\$$' "$ALLOWLIST_FILE"
}

@test "mcp rm removes claude.json entry" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers.filesystem // "null"' "$HOME/.claude.json"
    [ "$output" = "null" ]
}

@test "mcp rm fails for non-enabled server" {
    run "$HERMIT" mcp rm filesystem
    [ "$status" -ne 0 ]
    [[ "$output" == *"not enabled"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/mcp.bats`
Expected: FAIL

**Step 3: Implement `hermit mcp rm`**

Add inside the `mcp)` case:

```bash
        rm)
            shift
            _mcp_name="${1:-}"
            if [[ -z "$_mcp_name" ]]; then
                echo "Error: 'mcp rm' requires a server name" >&2
                exit 1
            fi
            _enabled="$SCRIPT_DIR/mcp/enabled/${_mcp_name}.yml"
            if [[ ! -f "$_enabled" ]]; then
                echo "Error: MCP server '$_mcp_name' is not enabled" >&2
                exit 1
            fi
            # Remove enabled file
            rm "$_enabled"
            # Remove allowlist entry
            _al_pattern="^mcp-${_mcp_name}$"
            _tmpfile="$(mktemp)"
            grep -vF "$_al_pattern" "$SCRIPT_DIR/tinyproxy/allowlist" > "$_tmpfile" || true
            mv "$_tmpfile" "$SCRIPT_DIR/tinyproxy/allowlist"
            # Remove from .claude.json
            _claude_json="$HOME/.claude.json"
            if [[ -s "$_claude_json" ]]; then
                _tmp_json="$(mktemp)"
                jq --arg name "$_mcp_name" 'del(.mcpServers[$name])' "$_claude_json" > "$_tmp_json"
                mv "$_tmp_json" "$_claude_json"
            fi
            echo "Disabled MCP server: $_mcp_name"
            if [[ "${HERMIT_NO_REBUILD:-}" != "1" ]]; then
                compose_cmd build
                compose_cmd up -d
            fi
            ;;
```

**Step 4: Run tests**

Run: `bats tests/mcp.bats`
Expected: PASS

**Step 5: Commit**

```bash
git add hermit tests/mcp.bats
git commit -m "feat(mcp): implement hermit mcp rm"
```

---

### Task 7: Implement `hermit mcp list`

Shows all available templates and which are enabled.

**Files:**
- Modify: `hermit`
- Modify: `tests/mcp.bats`

**Step 1: Write the failing test**

```bash
@test "mcp list shows available templates" {
    run "$HERMIT" mcp list
    [ "$status" -eq 0 ]
    [[ "$output" == *"filesystem"* ]]
    [[ "$output" == *"github"* ]]
}

@test "mcp list shows enabled status" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    run "$HERMIT" mcp list
    [ "$status" -eq 0 ]
    [[ "$output" == *"filesystem"* ]]
    [[ "$output" == *"enabled"* ]]
}
```

**Step 2: Implement**

```bash
        list)
            printf "%-15s %-10s %s\n" "NAME" "STATUS" "DESCRIPTION"
            for _tmpl in "$SCRIPT_DIR"/mcp/templates/*.yml; do
                [[ -e "$_tmpl" ]] || continue
                _name=$(grep '  name:' "$_tmpl" | head -1 | awk '{print $2}')
                _desc=$(grep '  description:' "$_tmpl" | head -1 | sed 's/.*description: *"//;s/"$//')
                if [[ -f "$SCRIPT_DIR/mcp/enabled/${_name}.yml" ]]; then
                    _status="enabled"
                else
                    _status="disabled"
                fi
                printf "%-15s %-10s %s\n" "$_name" "$_status" "$_desc"
            done
            ;;
```

**Step 3: Run tests, commit**

Run: `bats tests/mcp.bats`

```bash
git add hermit tests/mcp.bats
git commit -m "feat(mcp): implement hermit mcp list"
```

---

### Task 8: Implement `hermit mcp status` and `hermit mcp restart`

**Files:**
- Modify: `hermit`
- Modify: `tests/mcp.bats`

**Step 1: Write tests**

```bash
@test "mcp status runs without error" {
    run "$HERMIT" mcp status
    [ "$status" -eq 0 ]
}

@test "mcp restart runs without error when no servers enabled" {
    run "$HERMIT" mcp restart
    [ "$status" -eq 0 ]
}
```

**Step 2: Implement**

```bash
        status)
            _has_enabled=false
            for _f in "$SCRIPT_DIR"/mcp/enabled/*.yml; do
                [[ -e "$_f" ]] && _has_enabled=true && break
            done
            if [[ "$_has_enabled" == false ]]; then
                echo "No MCP servers enabled"
                exit 0
            fi
            compose_cmd ps --filter "name=mcp-"
            ;;
        restart)
            _has_enabled=false
            for _f in "$SCRIPT_DIR"/mcp/enabled/*.yml; do
                [[ -e "$_f" ]] && _has_enabled=true && break
            done
            if [[ "$_has_enabled" == false ]]; then
                echo "No MCP servers enabled"
                exit 0
            fi
            compose_cmd restart
            ;;
```

**Step 3: Run tests, commit**

Run: `bats tests/mcp.bats`

```bash
git add hermit tests/mcp.bats
git commit -m "feat(mcp): implement hermit mcp status and restart"
```

---

### Task 9: Update usage() and add mcp help

**Files:**
- Modify: `hermit:11-41` (usage function)

**Step 1: Update usage**

Add MCP subcommands to the usage output:

```
  mcp         Manage MCP servers (list/add/rm/status/restart)

MCP subcommands:
  mcp list                    List available MCP servers and their status
  mcp add <name>              Enable an MCP server (auto-rebuilds)
  mcp rm <name>               Disable an MCP server (auto-rebuilds)
  mcp status                  Show running MCP server containers
  mcp restart                 Restart MCP server containers
```

Also add a default case in the `mcp)` block that prints MCP-specific help.

**Step 2: Commit**

```bash
git add hermit
git commit -m "docs(mcp): add MCP subcommands to hermit usage"
```

---

### Task 10: Add doctor MCP checks

**Files:**
- Modify: `hermit` (doctor case block, around line 283-332)
- Modify: `tests/doctor.bats`

**Step 1: Write the failing test**

Add to `tests/doctor.bats` (or `tests/mcp.bats`):

```bash
@test "doctor checks MCP allowlist consistency" {
    # Add a server, then manually remove the allowlist entry to create orphan
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    # Remove allowlist entry manually
    sed -i '' '/^\\^mcp-filesystem/d' "$ALLOWLIST_FILE"
    run "$HERMIT" doctor
    [[ "$output" == *"FAIL"*"mcp-filesystem"* ]] || [[ "$output" == *"WARN"*"mcp-filesystem"* ]]
}
```

**Step 2: Implement MCP doctor checks**

Add to the `doctor)` block, after the existing checks:

```bash
# MCP consistency checks
for _enabled in "$SCRIPT_DIR"/mcp/enabled/*.yml; do
    [[ -e "$_enabled" ]] || continue
    _mcp_name=$(grep '  name:' "$_enabled" | head -1 | awk '{print $2}')
    _al_pattern="^mcp-${_mcp_name}$"

    printf "%-40s" "MCP allowlist: mcp-${_mcp_name}..."
    if grep -qF "$_al_pattern" "$SCRIPT_DIR/tinyproxy/allowlist"; then
        echo "PASS"
        _pass=$((_pass + 1))
    else
        echo "FAIL (missing allowlist entry)"
        _fail=$((_fail + 1))
    fi

    printf "%-40s" "MCP config: ${_mcp_name}..."
    if jq -e ".mcpServers.${_mcp_name}" "$HOME/.claude.json" &>/dev/null; then
        echo "PASS"
        _pass=$((_pass + 1))
    else
        echo "FAIL (missing from .claude.json)"
        _fail=$((_fail + 1))
    fi
done
```

**Step 3: Run tests, commit**

Run: `bats tests/mcp.bats tests/doctor.bats`

```bash
git add hermit tests/
git commit -m "feat(mcp): add MCP health checks to hermit doctor"
```

---

### Task 11: Update README and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Step 1: Add MCP section to README**

Add a new section after the existing "Allowlist" section covering:
- What MCP servers are and how they work in isolated crustacean
- How to list, add, remove servers
- How to create custom templates
- The template format (x-mcp fields)

**Step 2: Update CLAUDE.md**

Add MCP commands to the "Common Commands" section. Add a "MCP Servers" section explaining the architecture.

**Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add MCP server documentation"
```

---

### Task 12: Integration test - end to end MCP connectivity

This task requires running containers. It verifies that Claude Code can actually reach an MCP server through tinyproxy.

**Files:**
- Modify: `tests/mcp.bats`

**Step 1: Write integration test**

```bash
@test "enabled MCP server is reachable through proxy" {
    skip "requires MCP server images to be available"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    # Rebuild with MCP override included
    compose_cmd build
    compose_cmd up -d
    # Wait for MCP server to be ready
    sleep 3
    # Curl from claude-code container through proxy to MCP server
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://mcp-filesystem:3000/mcp"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
    compose_cmd down
}
```

This test is initially `skip`ped since it depends on real MCP server images. Remove the `skip` once images are available or after creating a minimal test image.

**Step 2: Commit**

```bash
git add tests/mcp.bats
git commit -m "test(mcp): add integration test for MCP connectivity"
```
