#!/usr/bin/env bats

load test_helper

# --- Guard: probe has required tools ---

@test "probe has curl and dig" {
    run run_in_container "command -v curl && command -v dig"
    [ "$status" -eq 0 ]
}

# --- Direct access (no proxy) ---

@test "direct HTTPS is blocked without proxy" {
    run run_in_container_no_proxy "curl -s -o /dev/null --max-time 5 https://google.com 2>&1; echo \$?"
    # Expect curl exit code 6 (resolve failure), 7 (connect failure), or 28 (timeout)
    _exit_code="${lines[-1]}"
    [[ "$_exit_code" == "6" ]] || [[ "$_exit_code" == "7" ]] || [[ "$_exit_code" == "28" ]]
}

@test "direct HTTP is blocked without proxy" {
    run run_in_container_no_proxy "curl -s -o /dev/null --max-time 5 http://example.com 2>&1; echo \$?"
    _exit_code="${lines[-1]}"
    [[ "$_exit_code" == "6" ]] || [[ "$_exit_code" == "7" ]] || [[ "$_exit_code" == "28" ]]
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
    # Proxy rejects CONNECT with 403
    run run_in_container "curl -s -o /dev/null -w '%{http_connect}' --max-time 10 https://google.com"
    [ "$output" = "403" ]
}

@test "non-allowlisted domain is blocked via proxy (evil.com)" {
    run run_in_container "curl -s -o /dev/null -w '%{http_connect}' --max-time 10 https://evil.com"
    [ "$output" = "403" ]
}

# --- Regex edge cases ---

@test "exact match rejects prefix mismatch" {
    # api.anthropic.com is ^api\.anthropic\.com$ - notapi.anthropic.com should not match
    run run_in_container "curl -s -o /dev/null -w '%{http_connect}' --max-time 10 https://notapi.anthropic.com"
    [ "$output" = "403" ]
}

@test "subdomain pattern matches subdomains" {
    # ^(.+\.)?github\.com$ allows raw.github.com and similar subdomains
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://raw.githubusercontent.com"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

@test "subdomain pattern allows base domain" {
    # ^(.+\.)?github\.com$ - the (...)? makes the subdomain optional, so github.com itself should match
    run run_in_container "curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://github.com"
    [ "$status" -eq 0 ]
    [[ "$output" != "000" ]]
}

# --- Port restrictions ---

@test "non-443 port is blocked via proxy" {
    # ConnectPort 443 only - HTTPS on port 8443 requires CONNECT which should be rejected with 403
    run run_in_container "curl -s -o /dev/null -w '%{http_connect}' --max-time 10 https://api.anthropic.com:8443"
    [ "$output" = "403" ]
}

# --- External DNS resolution ---

@test "external DNS does not resolve on internal network" {
    # Without DNS on the internal network, external domains should not resolve
    run run_in_container_no_proxy "dig +short +time=3 +tries=1 example.com"
    # Should produce empty output (no results)
    [ -z "$output" ]
}

# --- Claude-code image hardening ---

@test "claude-code image has no network exfil tools" {
    # curl, wget, nc, and dig should not be available in claude-code
    # command -v returns non-zero when command not found (bash returns 1, sh returns 127)
    run run_in_claude_container 'command -v curl && echo "ERROR: curl found" || echo "curl not found"'
    [[ "$output" == *"curl not found"* ]]

    run run_in_claude_container 'command -v wget && echo "ERROR: wget found" || echo "wget not found"'
    [[ "$output" == *"wget not found"* ]]

    run run_in_claude_container 'command -v nc && echo "ERROR: nc found" || echo "nc not found"'
    [[ "$output" == *"nc not found"* ]]

    run run_in_claude_container 'command -v dig && echo "ERROR: dig found" || echo "dig not found"'
    [[ "$output" == *"dig not found"* ]]
}

# --- Proxy environment (claude-code) ---

@test "HTTPS_PROXY is set correctly" {
    run run_in_claude_container 'echo $HTTPS_PROXY'
    [ "$output" = "http://tinyproxy:8888" ]
}

@test "HTTP_PROXY is set correctly" {
    run run_in_claude_container 'echo $HTTP_PROXY'
    [ "$output" = "http://tinyproxy:8888" ]
}
