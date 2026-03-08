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

setup() {
    cp "$ALLOWLIST_FILE" "$ALLOWLIST_FILE.bak"
    if [[ -f "$HOME/.claude.json" ]]; then
        cp "$HOME/.claude.json" "$HOME/.claude.json.bak"
    fi
}

teardown() {
    mv "$ALLOWLIST_FILE.bak" "$ALLOWLIST_FILE"
    if [[ -f "$HOME/.claude.json.bak" ]]; then
        mv "$HOME/.claude.json.bak" "$HOME/.claude.json"
    fi
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml
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
    run jq -r '.mcpServers.filesystem.url' "$HOME/.claude.json"
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
    run jq -r '.mcpServers.filesystem // "null"' "$HOME/.claude.json"
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
