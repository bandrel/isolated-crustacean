#!/usr/bin/env bats

load test_helper

_test_vol_prefix="hermittest"

setup() {
    _test_name="${_test_vol_prefix}-$$-${BATS_TEST_NUMBER}"
}

teardown() {
    # Clean up any test volumes (hermit prepends "isolated-crustaion-")
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
    run docker volume inspect "isolated-crustaion-${_test_name}"
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
    run docker volume inspect "isolated-crustaion-${_test_name}"
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
