#!/usr/bin/env bash
# Shared helpers for bats isolation tests

COMPOSE_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOWLIST_FILE="$COMPOSE_PROJECT_DIR/tinyproxy/allowlist"
HERMIT="$COMPOSE_PROJECT_DIR/hermit"

COMPOSE_FILES=(-f "$COMPOSE_PROJECT_DIR/docker-compose.yml")
for f in "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml; do
    [[ -e "$f" ]] && COMPOSE_FILES+=(-f "$f")
done

# Run a command inside the claude-code container with proxy env vars intact
run_in_container() {
    docker compose "${COMPOSE_FILES[@]}" \
        run --rm --no-deps -T --entrypoint bash claude-code -c "$1" 2>/dev/null
}

# Run a command inside the claude-code container with proxy env vars stripped
run_in_container_no_proxy() {
    docker compose "${COMPOSE_FILES[@]}" \
        run --rm --no-deps -T --entrypoint bash \
        -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= \
        claude-code -c "$1" 2>/dev/null
}
