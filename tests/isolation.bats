#!/usr/bin/env bats

load test_helper

# --- Direct access (no proxy) ---

@test "direct HTTPS is blocked without proxy" {
    run run_in_container_no_proxy "curl -s -o /dev/null --max-time 5 https://google.com 2>&1; echo \$?"
    # Expect a non-zero curl exit code (timeout or connection refused)
    [[ "${lines[-1]}" != "0" ]]
}

@test "direct HTTP is blocked without proxy" {
    run run_in_container_no_proxy "curl -s -o /dev/null --max-time 5 http://example.com 2>&1; echo \$?"
    [[ "${lines[-1]}" != "0" ]]
}

@test "internal DNS resolves container names" {
    # Docker embedded DNS resolves service names on the internal network
    run run_in_container "dig +short tinyproxy"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# --- Allowlist enforcement (via proxy) ---

@test "allowlisted domain succeeds via proxy" {
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://api.anthropic.com"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

@test "allowlisted subdomain succeeds via proxy" {
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://raw.githubusercontent.com"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

@test "non-allowlisted domain is blocked via proxy" {
    # Proxy rejects CONNECT with 403, causing curl to exit non-zero
    run run_in_container "curl -s -o /dev/null --max-time 10 https://google.com; echo \$?"
    [[ "${lines[-1]}" != "0" ]]
}

@test "non-allowlisted domain is blocked via proxy (evil.com)" {
    run run_in_container "curl -s -o /dev/null --max-time 10 https://evil.com; echo \$?"
    [[ "${lines[-1]}" != "0" ]]
}

# --- Regex edge cases ---

@test "exact match rejects prefix mismatch" {
    # api.anthropic.com is ^api\.anthropic\.com$ - notapi.anthropic.com should not match
    run run_in_container "curl -s -o /dev/null --max-time 10 https://notapi.anthropic.com; echo \$?"
    [[ "${lines[-1]}" != "0" ]]
}

@test "subdomain pattern matches subdomains" {
    # ^(.+\.)?sentry\.io$ allows foo.sentry.io
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://foo.sentry.io"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

@test "subdomain pattern allows base domain" {
    # ^(.+\.)?sentry\.io$ - the (...)? makes the subdomain optional, so sentry.io itself should match
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://sentry.io"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

# --- Port restrictions ---

@test "non-443 port is blocked via proxy" {
    # ConnectPort 443 only - HTTPS on port 8443 requires CONNECT which should be rejected
    run run_in_container "curl -s -o /dev/null --max-time 10 https://api.anthropic.com:8443; echo \$?"
    [[ "${lines[-1]}" != "0" ]]
}

# --- Proxy environment ---

@test "HTTPS_PROXY is set correctly" {
    run run_in_container 'echo $HTTPS_PROXY'
    [ "$output" = "http://tinyproxy:8888" ]
}

@test "HTTP_PROXY is set correctly" {
    run run_in_container 'echo $HTTP_PROXY'
    [ "$output" = "http://tinyproxy:8888" ]
}
