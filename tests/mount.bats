#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

# Mounting the checkout (or anything containing it) read-write would let a
# compromised container rewrite hermit / compose files / allowlist.
@test "start --mount refuses the hermit checkout itself" {
    run --separate-stderr "$HERMIT" start --mount "$COMPOSE_PROJECT_DIR"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
    [ ! -f "$_ws_override" ]
}

@test "start --mount refuses a parent of the hermit checkout" {
    run --separate-stderr "$HERMIT" start --mount "$COMPOSE_PROJECT_DIR/.."
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
    [ ! -f "$_ws_override" ]
}

@test "mcp sync-workspace --mount refuses the checkout and its parent" {
    run --separate-stderr "$HERMIT" mcp sync-workspace --mount "$COMPOSE_PROJECT_DIR"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
    run --separate-stderr "$HERMIT" mcp sync-workspace --mount "$COMPOSE_PROJECT_DIR/.."
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
    [ ! -f "$_ws_override" ]
}

@test "--mount refuses a symlink that resolves to a parent of the checkout" {
    ln -s "$COMPOSE_PROJECT_DIR/.." "$BATS_TEST_TMPDIR/link"
    run --separate-stderr "$HERMIT" mcp sync-workspace --mount "$BATS_TEST_TMPDIR/link"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
}

@test "--mount refuses subdirectories of the checkout" {
    # A writable mcp/ or tinyproxy/ would let the container drop an enabled
    # compose file or edit the allowlist that the host loads next run.
    for _sub in mcp tinyproxy tests; do
        run --separate-stderr "$HERMIT" mcp sync-workspace --mount "$COMPOSE_PROJECT_DIR/$_sub"
        [ "$status" -eq 1 ]
        [[ "$stderr" == *"Error: refusing to mount"* ]]
    done
    run --separate-stderr "$HERMIT" start --mount "$COMPOSE_PROJECT_DIR/mcp"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error: refusing to mount"* ]]
    [ ! -f "$_ws_override" ]
}

@test "--mount of an unrelated temp directory is accepted" {
    # Only the checkout, its ancestors, and its subdirectories are refused
    run "$HERMIT" mcp sync-workspace --mount "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Workspace: bind mount"* ]]
    [ "$(yq -r '.x-hermit.workspace_mode' "$_ws_override")" = "bind" ]
}
