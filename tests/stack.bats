#!/usr/bin/env bats

load test_helper

# Create a decoy container on ic-internal network with foreign project labels
setup() {
    # Generate a unique project name for the decoy
    export DECOY_PROJECT="bats-foreign-$$-$(date +%s)"
    export DECOY_WORKDIR="/nonexistent/bats-foreign"
}

teardown() {
    # Always remove the decoy to prevent breaking later tests
    docker rm -f "${DECOY_CONTAINER_ID:-nonexistent}" 2>/dev/null || true
}

@test "exec refuses to run when foreign stack is on ic-internal" {
    # Start a decoy container that shadows tinyproxy's name
    run docker run -d \
        --name "decoy-${DECOY_PROJECT}" \
        --network ic-internal \
        --label "com.docker.compose.project=$DECOY_PROJECT" \
        --label "com.docker.compose.project.working_dir=$DECOY_WORKDIR" \
        --label "com.docker.compose.service=tinyproxy" \
        alpine:latest sleep 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # exec must refuse and exit 1, with Error in stderr
    run "$HERMIT" exec true 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"$DECOY_PROJECT"* ]]
}

@test "doctor shows FAIL when foreign stack is on ic-internal" {
    # Start decoy
    run docker run -d \
        --name "decoy-${DECOY_PROJECT}" \
        --network ic-internal \
        --label "com.docker.compose.project=$DECOY_PROJECT" \
        --label "com.docker.compose.project.working_dir=$DECOY_WORKDIR" \
        --label "com.docker.compose.service=tinyproxy" \
        alpine:latest sleep 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # doctor must show FAIL for the check
    run "$HERMIT" doctor
    [ "$status" -ne 0 ]
    grep -q "Checking for other hermit stacks" <<<"$output"
    grep -Eq '^Checking for other hermit stacks[^[:cntrl:]]*FAIL' <<<"$output"
    [[ "$output" == *"$DECOY_PROJECT"* ]]
}

@test "status still works when foreign stack is on ic-internal" {
    # Start decoy
    run docker run -d \
        --name "decoy-${DECOY_PROJECT}" \
        --network ic-internal \
        --label "com.docker.compose.project=$DECOY_PROJECT" \
        --label "com.docker.compose.project.working_dir=$DECOY_WORKDIR" \
        --label "com.docker.compose.service=tinyproxy" \
        alpine:latest sleep 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # status must still work (exit 0, not refused)
    run "$HERMIT" status
    [ "$status" -eq 0 ]
}

@test "stop still works when foreign stack is on ic-internal" {
    # Start decoy
    run docker run -d \
        --name "decoy-${DECOY_PROJECT}" \
        --network ic-internal \
        --label "com.docker.compose.project=$DECOY_PROJECT" \
        --label "com.docker.compose.project.working_dir=$DECOY_WORKDIR" \
        --label "com.docker.compose.service=tinyproxy" \
        alpine:latest sleep 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # stop must still work (exit 0, not refused)
    run "$HERMIT" stop
    [ "$status" -eq 0 ]

    # Bring tinyproxy back up for other tests
    hermit_compose up -d tinyproxy
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
    # Start a container on ic-internal without proper labels
    run docker run -d \
        --name "decoy-no-label-$$" \
        --network ic-internal \
        alpine:latest sleep 300
    [ "$status" -eq 0 ]
    export DECOY_CONTAINER_ID="$output"

    # exec must refuse and exit 1, with Error in stderr
    run "$HERMIT" exec true 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error:"* ]]
}
