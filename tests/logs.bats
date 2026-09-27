#!/usr/bin/env bats

load test_helper

@test "logs --blocked filters to denied entries" {
    # Test the grep pattern against sample tinyproxy log lines
    sample="CONNECT   Jan 01 00:00:00 [1]: Proxying allowed to api.anthropic.com
CONNECT   Jan 01 00:00:01 [1]: Refused connection from client
CONNECT   Jan 01 00:00:02 [1]: Proxying refused on filter rule for google.com"
    run bash -c "echo '$sample' | grep -iE 'refused|denied|blocked'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Refused"* ]]
    [[ "$output" == *"refused on filter"* ]]
    [[ "$output" != *"Proxying allowed"* ]]
}

@test "logs --blocked with no matches exits non-zero" {
    sample="CONNECT   Jan 01 00:00:00 [1]: Proxying allowed to api.anthropic.com"
    run bash -c "echo '$sample' | grep -iE 'refused|denied|blocked'"
    [ "$status" -ne 0 ]
}

@test "logs captures real tinyproxy denials" {
    # Trigger a denied CONNECT request to a non-allowlisted host
    run_in_container "curl -s -o /dev/null --max-time 10 https://evil.com 2>&1" >/dev/null 2>&1 || true
    # Wait for logs to be written
    sleep 1
    # Check that hermit logs shows the denial (contains "refused")
    run bash -c "./hermit logs"
    [[ "$output" == *"refused"* ]] || [[ "$output" == *"blocked"* ]] || [[ "$output" == *"denied"* ]]
}

@test "logs --blocked shows denied hostname" {
    # Trigger a denied CONNECT request to a non-allowlisted host
    run_in_container "curl -s -o /dev/null --max-time 10 https://evil.com 2>&1" >/dev/null 2>&1 || true
    # Wait for logs to be written
    sleep 1
    # Check that hermit logs --blocked output contains the hostname and is not just a fallback message
    run bash -c "./hermit logs --blocked"
    [[ "$output" != "(no blocked requests found)" ]]
    [[ "$output" == *"evil"* ]]
}
