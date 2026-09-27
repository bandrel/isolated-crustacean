#!/usr/bin/env bats

load test_helper

@test "doctor output contains proxy check label" {
    run "$HERMIT" doctor
    [[ "$output" == *"proxy"* ]] || [[ "$output" == *"Proxy"* ]] || [[ "$output" == *"tinyproxy"* ]]
}

@test "doctor DNS check passes" {
    run "$HERMIT" doctor
    [[ "$output" =~ Checking[[:space:]]+DNS.*PASS ]]
}

@test "doctor allowed domain check passes" {
    run "$HERMIT" doctor
    [[ "$output" =~ Checking[[:space:]]+allowed.*PASS ]]
}

@test "doctor blocked domain check passes" {
    run "$HERMIT" doctor
    [[ "$output" =~ Checking[[:space:]]+blocked.*PASS ]]
}

@test "doctor exits 0 with no MCP servers enabled" {
    run "$HERMIT" doctor
    [ "$status" -eq 0 ]
}
