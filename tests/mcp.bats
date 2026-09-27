#!/usr/bin/env bats

load test_helper

@test "internal network has explicit name" {
    run docker compose -f "$COMPOSE_PROJECT_DIR/docker-compose.yml" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: ic-internal"* ]]
}

@test "hermit status works with no MCP servers enabled" {
    run "$HERMIT" status
    [ "$status" -eq 0 ]
}

@test "all templates have required x-mcp fields" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        for field in name description transport port path; do
            run yq -e ".x-mcp.$field" "$tmpl"
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
        name=$(yq -r '.x-mcp.name' "$tmpl")
        run grep "  mcp-${name}:" "$tmpl"
        [ "$status" -eq 0 ] || {
            echo "Service mcp-${name} not found in $(basename "$tmpl")"
            return 1
        }
    done
}

setup() {
    cp "$ALLOWLIST_FILE" "$ALLOWLIST_FILE.bak"
}

teardown() {
    mv "$ALLOWLIST_FILE.bak" "$ALLOWLIST_FILE"
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/templates/test-hyphen.yml
}

@test "all templates reference the ic-internal network" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        run grep "name: ic-internal" "$tmpl"
        [ "$status" -eq 0 ] || {
            echo "Missing ic-internal network in $(basename "$tmpl")"
            return 1
        }
    done
}

@test "mcp add copies template to enabled" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [ -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}

@test "mcp add adds allowlist entry" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    grep -q '^\^mcp-filesystem\$$' "$ALLOWLIST_FILE"
}

@test "mcp add updates claude.json mcpServers" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers.filesystem.url' "$HERMIT_CONFIG_DIR/claude.json"
    [ "$output" = "http://mcp-filesystem:3000/mcp" ]
}

@test "mcp add fails for nonexistent template" {
    run "$HERMIT" mcp add nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "mcp add warns on duplicate" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled"* ]]
}

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
    run jq -r '.mcpServers.filesystem // "null"' "$HERMIT_CONFIG_DIR/claude.json"
    [ "$output" = "null" ]
}

@test "mcp rm fails for non-enabled server" {
    run "$HERMIT" mcp rm filesystem
    [ "$status" -ne 0 ]
    [[ "$output" == *"not enabled"* ]]
}

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

@test "mcp status runs without error" {
    run "$HERMIT" mcp status
    [ "$status" -eq 0 ]
}

@test "mcp restart runs without error when no servers enabled" {
    run "$HERMIT" mcp restart
    [ "$status" -eq 0 ]
}

@test "doctor checks MCP allowlist consistency" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    # Remove allowlist entry manually to create inconsistency
    _tmpfile="$(mktemp)"
    grep -v 'mcp-filesystem' "$ALLOWLIST_FILE" > "$_tmpfile" || true
    mv "$_tmpfile" "$ALLOWLIST_FILE"
    run "$HERMIT" doctor
    # Doctor should report FAIL on the mcp-filesystem allowlist line (anchor to line start)
    grep -Eq '^MCP allowlist: mcp-filesystem[^[:cntrl:]]*FAIL' <<<"$output"
    # Doctor should exit non-zero when there's an inconsistency
    [ "$status" -ne 0 ]
}

@test "enabled MCP server is reachable through proxy" {
    skip "requires MCP server images to be available"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    compose_cmd build
    compose_cmd up -d
    sleep 3
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://mcp-filesystem:3000/mcp"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
    compose_cmd down
}

@test "docker compose config uses HERMIT_CONFIG_DIR for mounts" {
    run docker compose -f "$COMPOSE_PROJECT_DIR/docker-compose.yml" config
    [ "$status" -eq 0 ]
    # Should contain HERMIT_CONFIG_DIR paths in long-form volume source
    grep -q "source: ${HERMIT_CONFIG_DIR}/claude" <<<"$output"
    # Should NOT contain the host's HOME directory as mount source (long-form)
    ! grep -q "source: ${HOME}/.claude" <<<"$output"
}

@test "mcp add does not modify host ~/.claude.json" {
    _host_json="$HOME/.claude.json"
    # Skip if host's ~/.claude.json doesn't exist
    [[ -f "$_host_json" ]] || skip "host ~/.claude.json not present"

    # Capture checksum before
    _checksum_before="$(shasum -a 256 "$_host_json" | awk '{print $1}')"

    # Run mcp add with HERMIT_NO_REBUILD
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]

    # Checksum should be identical (host file untouched)
    _checksum_after="$(shasum -a 256 "$_host_json" | awk '{print $1}')"
    [ "$_checksum_before" = "$_checksum_after" ]
}

@test "doctor MCP config check works for hyphenated server names" {
    # Create a temporary template with a hyphenated name
    _temp_tmpl="$COMPOSE_PROJECT_DIR/mcp/templates/test-hyphen.yml"
    cat > "$_temp_tmpl" <<'EOF'
services:
  mcp-test-hyphen:
    image: alpine:3.21
    networks:
      - ic-internal

x-mcp:
  name: test-hyphen
  description: Test template with hyphenated name
  transport: stdio
  port: 3000
  path: /mcp

networks:
  ic-internal:
    name: ic-internal
    external: true
EOF

    # Add the MCP server
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add test-hyphen
    [ "$status" -eq 0 ]

    # Doctor should handle hyphenated names correctly
    run "$HERMIT" doctor
    # Should check the hyphenated server name without error
    [ "$status" -eq 0 ]
    [[ "$output" == *"MCP allowlist: mcp-test-hyphen"* ]]
    [[ "$output" == *"MCP config: test-hyphen"* ]]
}
