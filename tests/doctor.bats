#!/usr/bin/env bats

load test_helper

@test "doctor output contains proxy check label" {
    run "$HERMIT" doctor
    [[ "$output" == *"proxy"* ]] || [[ "$output" == *"Proxy"* ]] || [[ "$output" == *"tinyproxy"* ]]
}

@test "doctor output contains DNS check label" {
    run "$HERMIT" doctor
    [[ "$output" == *"DNS"* ]] || [[ "$output" == *"dns"* ]]
}

@test "doctor output contains allowed domain check" {
    run "$HERMIT" doctor
    [[ "$output" == *"allowed"* ]] || [[ "$output" == *"Allowed"* ]] || [[ "$output" == *"allowlist"* ]]
}

@test "doctor output contains blocked domain check" {
    run "$HERMIT" doctor
    [[ "$output" == *"blocked"* ]] || [[ "$output" == *"Blocked"* ]] || [[ "$output" == *"denied"* ]]
}
