#!/usr/bin/env bats

load test_helper

_test_vol_prefix="hermittest"

setup() {
    _test_name="${_test_vol_prefix}-$$-${BATS_TEST_NUMBER}"
}

teardown() {
    # Clean up any test volumes (both isolated-crustacean- and isolated-crustaion-)
    docker volume ls --filter "name=isolated-crustacean-${_test_vol_prefix}" -q | xargs -r docker volume rm 2>/dev/null || true
    docker volume ls --filter "name=isolated-crustaion-${_test_vol_prefix}" -q | xargs -r docker volume rm 2>/dev/null || true
    rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"
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
    run "$HERMIT" workspace current
    [ "$status" -eq 0 ]
    # workspace current prints volume name to stdout and note to stderr
    # The note is part of $output in bats, so check if volume name is in output
    [[ "$output" == "$_legacy_vol"* ]]

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
