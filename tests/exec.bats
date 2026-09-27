#!/usr/bin/env bats

load test_helper

@test "exec runs a command and returns output" {
    run "$HERMIT" exec echo hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "exec with no args shows usage error" {
    run "$HERMIT" exec
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"requires"* ]]
}

@test "entrypoint works without TTY (non-interactive)" {
    # Test real entrypoint behavior: no TTY, must not fail, claude --version must work
    # Use docker compose run --no-deps -T (no TTY) to verify entrypoint handles non-TTY correctly
    export HERMIT_CONFIG_DIR=$(mktemp -d)
    run docker compose run --rm --no-deps -T claude-code --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+\ \(Claude\ Code\) ]]
    rm -rf "$HERMIT_CONFIG_DIR"
}
