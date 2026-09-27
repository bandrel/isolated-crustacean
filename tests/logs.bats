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

@test "logs command succeeds and contains no permission errors" {
    # Verify that hermit logs works and shows startup, with no permission denied error
    run "$HERMIT" logs
    [ "$status" -eq 0 ]
    [[ "$output" != *"Could not create file"* ]]
    [[ "$output" == *"Starting main loop"* ]] || [[ "$output" == *"Initializing"* ]]
}

@test "logs --blocked captures real denied hostname" {
    # Use a unique hostname for this test to isolate from other test requests
    local _host="logstest-${RANDOM}${RANDOM}.invalid"
    # Trigger a denied CONNECT request to that host via the probe
    run_in_container "curl -s -o /dev/null --max-time 10 https://${_host} 2>&1" >/dev/null 2>&1 || true
    # Wait for logs to be written
    sleep 1
    # Check that hermit logs --blocked shows the denial with the exact hostname
    run "$HERMIT" logs --blocked
    [ "$status" -eq 0 ]
    [[ "$output" != "(no blocked requests found)" ]]
    # Match the exact log line format: "Proxying refused on filtered domain"
    [[ "$output" == *"$_host"* ]]
    [[ "$output" == *"refused"* ]]
}
