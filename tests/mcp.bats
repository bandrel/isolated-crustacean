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
