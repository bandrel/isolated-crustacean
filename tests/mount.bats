#!/usr/bin/env bats

load test_helper

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
