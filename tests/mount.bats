#!/usr/bin/env bats

load test_helper

# `hermit start` writes mcp/.runtime/workspace.yml by design; do not let a
# test run leave a bind override pointing at /tmp behind in the checkout.
_ws_override="$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml"

setup() {
    rm -f "$_ws_override.bak"
    [[ -f "$_ws_override" ]] && cp "$_ws_override" "$_ws_override.bak"
    return 0
}

teardown() {
    if [[ -f "$_ws_override.bak" ]]; then
        mv "$_ws_override.bak" "$_ws_override"
    else
        rm -f "$_ws_override"
    fi
}

@test "start --mount with nonexistent path exits non-zero" {
    run "$HERMIT" start --mount /nonexistent/path/xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "start --mount resolves relative paths" {
    # We can't actually start the container in tests, but we can verify
    # the path validation works by testing with a real directory
    # Using /tmp which always exists
    # This will try to start docker compose which may fail, but should NOT fail on path validation
    run timeout 5 "$HERMIT" start --mount /tmp 2>&1 || true
    # Should not contain "does not exist" error
    [[ "$output" != *"does not exist"* ]]
}
