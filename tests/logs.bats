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
