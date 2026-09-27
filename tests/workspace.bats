#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

_test_vol_prefix="hermittest"
_hermit_workspace_bak=""
_non_ws_vol=""
_ws_override="$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml"

setup() {
    _test_name="${_test_vol_prefix}-$$-${BATS_TEST_NUMBER}"
    # Save .hermit-workspace if it exists
    if [[ -f "$COMPOSE_PROJECT_DIR/.hermit-workspace" ]]; then
        _hermit_workspace_bak="$(cat "$COMPOSE_PROJECT_DIR/.hermit-workspace")"
    else
        _hermit_workspace_bak=""
    fi
    # Preserve any runtime override the user has; tests below create their own
    rm -f "$_ws_override.bak"
    [[ -f "$_ws_override" ]] && cp "$_ws_override" "$_ws_override.bak"
    return 0
}

teardown() {
    # Clean up any test volumes (both isolated-crustacean- and isolated-crustaion- with anchored filters)
    docker volume ls --filter "name=^isolated-crustacean-${_test_vol_prefix}" -q | xargs -r docker volume rm 2>/dev/null || true
    docker volume ls --filter "name=^isolated-crustaion-${_test_vol_prefix}" -q | xargs -r docker volume rm 2>/dev/null || true
    # Underscore-named decoy volume (not matched by the anchored filters above)
    [[ -n "$_non_ws_vol" ]] && docker volume rm "$_non_ws_vol" >/dev/null 2>&1 || true
    # Restore .hermit-workspace if it existed before
    if [[ -n "$_hermit_workspace_bak" ]]; then
        echo "$_hermit_workspace_bak" > "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    else
        rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    fi
    if [[ -f "$_ws_override.bak" ]]; then
        mv "$_ws_override.bak" "$_ws_override"
    else
        rm -f "$_ws_override"
    fi
}

@test "workspace list runs without error" {
    run "$HERMIT" workspace list
    [ "$status" -eq 0 ]
}

@test "workspace create makes a new volume" {
    run "$HERMIT" workspace create "$_test_name"
    [ "$status" -eq 0 ]
    run docker volume inspect "isolated-crustacean-${_test_name}"
    [ "$status" -eq 0 ]
}

@test "workspace create duplicate exits non-zero" {
    "$HERMIT" workspace create "$_test_name"
    run "$HERMIT" workspace create "$_test_name"
    [ "$status" -ne 0 ]
}

@test "workspace switch updates .hermit-workspace" {
    "$HERMIT" workspace create "$_test_name"
    run "$HERMIT" workspace switch "$_test_name"
    [ "$status" -eq 0 ]
    [ "$(cat "$COMPOSE_PROJECT_DIR/.hermit-workspace")" = "$_test_name" ]
}

@test "workspace switch to nonexistent volume exits non-zero" {
    run "$HERMIT" workspace switch "nonexistent-volume-xyz"
    [ "$status" -ne 0 ]
}

@test "workspace rm removes a volume" {
    "$HERMIT" workspace create "$_test_name"
    run bash -c "echo y | '$HERMIT' workspace rm '$_test_name'"
    [ "$status" -eq 0 ]
    run docker volume inspect "isolated-crustacean-${_test_name}"
    [ "$status" -ne 0 ]
}

@test "workspace rm nonexistent exits non-zero" {
    run bash -c "echo y | '$HERMIT' workspace rm 'nonexistent-xyz'"
    [ "$status" -ne 0 ]
}

@test "workspace with no subcommand defaults to list" {
    run "$HERMIT" workspace
    [ "$status" -eq 0 ]
}

@test "workspace create with no name exits non-zero" {
    run "$HERMIT" workspace create
    [ "$status" -ne 0 ]
}

@test "legacy-prefixed volume appears in list" {
    # Create a legacy-prefixed volume manually
    _legacy_vol="isolated-crustaion-${_test_name}"
    docker volume create "$_legacy_vol"

    run "$HERMIT" workspace list
    [ "$status" -eq 0 ]
    [[ "$output" == *"$_legacy_vol"* ]]

    # Clean up the legacy volume
    docker volume rm "$_legacy_vol"
}

@test "switch to legacy-prefixed volume works" {
    # Create a legacy-prefixed volume manually
    _legacy_vol="isolated-crustaion-${_test_name}"
    docker volume create "$_legacy_vol"

    run "$HERMIT" workspace switch "$_test_name"
    [ "$status" -eq 0 ]
    [ "$(cat "$COMPOSE_PROJECT_DIR/.hermit-workspace")" = "$_test_name" ]

    # Clean up the legacy volume
    docker volume rm "$_legacy_vol"
}

@test "workspace current shows legacy volume name when switched" {
    # Create a legacy-prefixed volume manually
    _legacy_vol="isolated-crustaion-${_test_name}"
    docker volume create "$_legacy_vol"

    "$HERMIT" workspace switch "$_test_name" &>/dev/null
    run --separate-stderr "$HERMIT" workspace current
    [ "$status" -eq 0 ]
    # Stdout should contain only the volume name with newline
    [ "$output" = "$_legacy_vol" ]
    # Stderr should contain the note
    [[ "$stderr" == Note:* ]]

    # Clean up the legacy volume
    docker volume rm "$_legacy_vol"
}

@test "rm removes legacy-prefixed volume" {
    # Create a legacy-prefixed volume manually
    _legacy_vol="isolated-crustaion-${_test_name}"
    docker volume create "$_legacy_vol"

    run bash -c "echo y | '$HERMIT' workspace rm '$_test_name'"
    [ "$status" -eq 0 ]

    # Verify the legacy volume is removed
    run docker volume inspect "$_legacy_vol"
    [ "$status" -ne 0 ]
}

@test "workspace create fails if name exists under legacy prefix" {
    # Create a legacy-prefixed volume manually
    _legacy_vol="isolated-crustaion-${_test_name}"
    docker volume create "$_legacy_vol"

    run "$HERMIT" workspace create "$_test_name"
    [ "$status" -ne 0 ]

    # Clean up the legacy volume
    docker volume rm "$_legacy_vol"
}

@test "workspace current prints ic-workspace when no .hermit-workspace exists" {
    # Ensure .hermit-workspace does not exist
    rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"

    run "$HERMIT" workspace current
    [ "$status" -eq 0 ]
    [ "$output" = "ic-workspace" ]
}

@test "workspace list does not show non-workspace volumes with underscore naming" {
    # Create a volume with underscore naming (not a workspace)
    _non_ws_vol="isolated-crustaion_bats-${RANDOM}"
    docker volume create "$_non_ws_vol"

    run "$HERMIT" workspace list
    [ "$status" -eq 0 ]
    # Non-workspace volume should not appear in list (removed in teardown)
    [[ ! "$output" =~ $_non_ws_vol ]]
}

@test "workspace switch repins an existing runtime override to the new volume" {
    "$HERMIT" workspace create "$_test_name"
    # Override pinned to the default volume (as hermit start would leave it)
    rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    "$HERMIT" mcp sync-workspace
    [ "$(yq -r '.volumes.workspace.name' "$_ws_override")" = "ic-workspace" ]
    run "$HERMIT" workspace switch "$_test_name"
    [ "$status" -eq 0 ]
    [ "$(yq -r '.volumes.workspace.name' "$_ws_override")" = "isolated-crustacean-${_test_name}" ]
    # exec/shell use hermit's compose set, so the resolved mount follows too
    [ "$(workspace_mount_source claude-code /home/node/workspace)" = "isolated-crustacean-${_test_name}" ]
}

@test "workspace switch leaves things alone when no runtime override exists" {
    "$HERMIT" workspace create "$_test_name"
    rm -f "$_ws_override"
    run "$HERMIT" workspace switch "$_test_name"
    [ "$status" -eq 0 ]
    [ ! -f "$_ws_override" ]
}

@test "workspace rm of the active workspace repins the override to ic-workspace" {
    "$HERMIT" workspace create "$_test_name"
    "$HERMIT" workspace switch "$_test_name"
    "$HERMIT" mcp sync-workspace
    [ "$(yq -r '.volumes.workspace.name' "$_ws_override")" = "isolated-crustacean-${_test_name}" ]
    run bash -c "echo y | '$HERMIT' workspace rm '$_test_name'"
    [ "$status" -eq 0 ]
    [ ! -f "$COMPOSE_PROJECT_DIR/.hermit-workspace" ]
    [ "$(yq -r '.volumes.workspace.name' "$_ws_override")" = "ic-workspace" ]
}
