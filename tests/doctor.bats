#!/usr/bin/env bats

load test_helper

@test "doctor output contains proxy check label" {
    run "$HERMIT" doctor
    [[ "$output" == *"proxy"* ]] || [[ "$output" == *"Proxy"* ]] || [[ "$output" == *"tinyproxy"* ]]
}

@test "doctor DNS check passes" {
    run "$HERMIT" doctor
    # Anchor to line start and use [^[:cntrl:]]* to avoid matching across lines
    grep -Eq '^Checking DNS resolution[^[:cntrl:]]*PASS' <<<"$output"
}

@test "doctor allowed domain check passes" {
    run "$HERMIT" doctor
    # Anchor to line start and use [^[:cntrl:]]* to avoid matching across lines
    grep -Eq '^Checking allowed domain reachable[^[:cntrl:]]*PASS' <<<"$output"
}

@test "doctor blocked domain check passes" {
    run "$HERMIT" doctor
    # Anchor to line start and use [^[:cntrl:]]* to avoid matching across lines
    grep -Eq '^Checking blocked domain denied[^[:cntrl:]]*PASS' <<<"$output"
}

@test "doctor exits 0 with no MCP servers enabled" {
    run "$HERMIT" doctor
    [ "$status" -eq 0 ]
}
