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
