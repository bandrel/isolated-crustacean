#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

# Get the built tinyproxy image (guaranteed after ./hermit build)
get_decoy_image() {
    local _img
    _img="$(hermit_compose images -q tinyproxy 2>/dev/null | head -1)"
    if [[ -z "$_img" ]]; then
        echo "Error: tinyproxy image not found; run ./hermit build first" >&2
        return 1
    fi
    echo "$_img"
}

setup() {
    export DECOY_IMAGE=$(get_decoy_image)
    export RESTORE_TINYPROXY=false
}

teardown() {
    # Always remove the decoy to prevent breaking later tests
    docker rm -f "${DECOY_CONTAINER_ID:-nonexistent}" 2>/dev/null || true
    # Restore tinyproxy if a test stopped it
    if [[ "${RESTORE_TINYPROXY}" == true ]]; then
        hermit_compose up -d tinyproxy 2>/dev/null || true
    fi
}

@test "exec refuses to run when foreign stack is on ic-internal" {
    local _decoy_project="bats-foreign-$BATS_TEST_NUMBER-$RANDOM"
    local _decoy_workdir="/nonexistent/bats-foreign"
    local _decoy_name="decoy-$_decoy_project"

    # Start a decoy container that shadows tinyproxy's name
    run docker run -d \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=$_decoy_project" \
        --label "com.docker.compose.project.working_dir=$_decoy_workdir" \
        --label "com.docker.compose.service=tinyproxy" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # exec must refuse and exit 1, with Error in stderr
    run "$HERMIT" exec true 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"$_decoy_project"* ]]
}

@test "doctor shows FAIL when foreign stack is on ic-internal" {
    local _decoy_project="bats-foreign-$BATS_TEST_NUMBER-$RANDOM"
    local _decoy_workdir="/nonexistent/bats-foreign"
    local _decoy_name="decoy-$_decoy_project"

    # Start decoy
    run docker run -d \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=$_decoy_project" \
        --label "com.docker.compose.project.working_dir=$_decoy_workdir" \
        --label "com.docker.compose.service=tinyproxy" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # doctor must show FAIL for the check
    run "$HERMIT" doctor
    [ "$status" -ne 0 ]
    grep -q "Checking for other hermit stacks" <<<"$output"
    grep -Eq '^Checking for other hermit stacks[^[:cntrl:]]*FAIL' <<<"$output"
    [[ "$output" == *"$_decoy_project"* ]]
}

@test "status still works when foreign stack is on ic-internal" {
    local _decoy_project="bats-foreign-$BATS_TEST_NUMBER-$RANDOM"
    local _decoy_workdir="/nonexistent/bats-foreign"
    local _decoy_name="decoy-$_decoy_project"

    # Start decoy
    run docker run -d \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=$_decoy_project" \
        --label "com.docker.compose.project.working_dir=$_decoy_workdir" \
        --label "com.docker.compose.service=tinyproxy" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # status must still work (exit 0, not refused)
    run "$HERMIT" status
    [ "$status" -eq 0 ]
}

@test "stop still works when foreign stack is on ic-internal" {
    local _decoy_project="bats-foreign-$BATS_TEST_NUMBER-$RANDOM"
    local _decoy_workdir="/nonexistent/bats-foreign"
    local _decoy_name="decoy-$_decoy_project"

    # Start decoy
    run docker run -d \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=$_decoy_project" \
        --label "com.docker.compose.project.working_dir=$_decoy_workdir" \
        --label "com.docker.compose.service=tinyproxy" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # stop must still work (exit 0, not refused)
    run "$HERMIT" stop
    [ "$status" -eq 0 ]
    # Signal teardown to restore tinyproxy
    export RESTORE_TINYPROXY=true
}

@test "exec succeeds without foreign stack" {
    run "$HERMIT" exec true
    [ "$status" -eq 0 ]
}

@test "doctor shows PASS for sole stack check without foreign stack" {
    run "$HERMIT" doctor
    [ "$status" -eq 0 ]
    grep -Eq '^Checking for other hermit stacks[^[:cntrl:]]*PASS' <<<"$output"
}

@test "exec refuses to run with container missing project label" {
    local _decoy_name="decoy-no-label-$BATS_TEST_NUMBER-$RANDOM"

    # Start a container with empty project label (treated same as missing)
    # Use tinyproxy image with --label key= to override the compose labels with empty values
    run docker run -d \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=" \
        --label "com.docker.compose.service=" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # exec must refuse and exit 1, with specific Error message
    run "$HERMIT" exec true 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: Found running container on ic-internal with no project label"* ]]
    [[ "$output" == *"$_decoy_name"* ]]
}

@test "exec allows stopped container with foreign project label" {
    # Create (but don't start) a container on ic-internal with foreign labels
    # Stopped containers don't hold DNS aliases, so they shouldn't block exec
    local _decoy_name="decoy-stopped-$BATS_TEST_NUMBER-$RANDOM"

    run docker create \
        --name "$_decoy_name" \
        --network ic-internal \
        --label "com.docker.compose.project=foreign-stopped" \
        --label "com.docker.compose.project.working_dir=/tmp" \
        --label "com.docker.compose.service=tinyproxy" \
        --entrypoint sleep "$DECOY_IMAGE" 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # exec must SUCCEED - stopped containers don't block
    run "$HERMIT" exec true
    [ "$status" -eq 0 ]
}
