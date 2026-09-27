#!/usr/bin/env bash
# Shared helpers for bats isolation tests

COMPOSE_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_FILE="$COMPOSE_PROJECT_DIR/tinyproxy/allowlist"
HERMIT="$COMPOSE_PROJECT_DIR/hermit"

# Create a temporary config directory for each test run
export HERMIT_CONFIG_DIR="$(mktemp -d)"

COMPOSE_FILES=(-f "$COMPOSE_PROJECT_DIR/docker-compose.yml")
for f in "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml; do
    [[ -e "$f" ]] && COMPOSE_FILES+=(-f "$f")
done

# Run a command inside the probe container with proxy env vars intact
run_in_container() {
    docker compose "${COMPOSE_FILES[@]}" --profile probe \
        run --rm --no-deps -T --entrypoint bash probe -c "$1" 2>/dev/null
}

# Run a command inside the probe container with proxy env vars stripped
run_in_container_no_proxy() {
    docker compose "${COMPOSE_FILES[@]}" --profile probe \
        run --rm --no-deps -T --entrypoint bash \
        -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= \
        probe -c "$1" 2>/dev/null
}

# Run a command inside the claude-code container with proxy env vars intact
run_in_claude_container() {
    docker compose "${COMPOSE_FILES[@]}" \
        run --rm --no-deps -T --entrypoint bash claude-code -c "$1" 2>/dev/null
}

# docker compose with the same file set hermit's compose_cmd uses, evaluated
# at call time: base + every currently enabled MCP file + the runtime
# workspace override (last, so it wins the merge). Use for tests that enable
# MCP servers mid-run.
hermit_compose() {
    local -a _files=(-f "$COMPOSE_PROJECT_DIR/docker-compose.yml")
    local _f
    for _f in "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml; do
        [[ -e "$_f" ]] && _files+=(-f "$_f")
    done
    [[ -e "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml" ]] \
        && _files+=(-f "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")
    docker compose "${_files[@]}" "$@"
}

# Print the mount source for <service>'s <container-path> from resolved
# compose config: the volume *name* for named volumes, the host path for binds.
workspace_mount_source() {
    local _svc="$1" _target="$2"
    hermit_compose config --format json 2>/dev/null | jq -r --arg svc "$_svc" --arg t "$_target" '
        (.volumes // {}) as $vols
        | .services[$svc].volumes[] | select(.target == $t)
        | if .type == "volume" then ($vols[.source].name // .source) else .source end'
}

# Minimal MCP initialize request body (JSON-RPC 2.0)
MCP_INIT_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"hermit-test","version":"0"}}}'

# POST an MCP initialize to http://mcp-<name>:<port>/mcp from the probe
# container (through tinyproxy) and print the response body.
mcp_initialize_via_proxy() {
    local _name="$1" _port="$2"
    run_in_container "curl -s --max-time 30 -X POST \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '$MCP_INIT_BODY' http://mcp-${_name}:${_port}/mcp"
}
