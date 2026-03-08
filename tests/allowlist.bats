#!/usr/bin/env bats

load test_helper

hermit_allowlist() {
    "$HERMIT" allowlist --allowlist-file "$TMPFILE" "$@"
}

setup() {
    TMPFILE="$(mktemp)"
    # Seed with a couple of known patterns
    cat >"$TMPFILE" <<'EOF'
^api\.anthropic\.com$
^(.+\.)?sentry\.io$
EOF
}

teardown() {
    rm -f "$TMPFILE"
}

@test "allowlist list prints entries" {
    run hermit_allowlist list
    [ "$status" -eq 0 ]
    [[ "$output" == *"api\.anthropic\.com"* ]]
    [[ "$output" == *"sentry\.io"* ]]
}

@test "allowlist add appends exact match pattern" {
    run hermit_allowlist add example.com
    [ "$status" -eq 0 ]
    grep -qF '^example\.com$' "$TMPFILE"
}

@test "allowlist add --subdomains appends subdomain pattern" {
    run hermit_allowlist add --subdomains example.com
    [ "$status" -eq 0 ]
    grep -qF '^(.+\.)?example\.com$' "$TMPFILE"
}

@test "allowlist add duplicate prints warning and does not duplicate" {
    hermit_allowlist add example.com
    count_before=$(grep -cF '^example\.com$' "$TMPFILE")
    run hermit_allowlist add example.com
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]] || [[ "$output" == *"duplicate"* ]]
    count_after=$(grep -cF '^example\.com$' "$TMPFILE")
    [ "$count_after" -eq "$count_before" ]
}

@test "allowlist remove deletes matching entry" {
    hermit_allowlist add example.com
    run hermit_allowlist remove example.com
    [ "$status" -eq 0 ]
    ! grep -qF 'example\.com' "$TMPFILE"
}

@test "allowlist remove nonexistent domain exits non-zero" {
    run hermit_allowlist remove nonexistent.com
    [ "$status" -ne 0 ]
    [ -n "$output" ]
}

@test "allowlist check exits 0 when domain matches" {
    run hermit_allowlist check api.anthropic.com
    [ "$status" -eq 0 ]
}

@test "allowlist check exits 1 when domain does not match" {
    run hermit_allowlist check evil.com
    [ "$status" -eq 1 ]
}

@test "allowlist with no subcommand defaults to list" {
    run hermit_allowlist
    [ "$status" -eq 0 ]
    [[ "$output" == *"api\.anthropic\.com"* ]]
}

@test "allowlist add with no domain exits non-zero" {
    run hermit_allowlist add
    [ "$status" -ne 0 ]
    [ -n "$output" ]
}

# --- Profile tests ---

hermit_allowlist_profile() {
    "$HERMIT" allowlist --allowlist-file "$TMPFILE" profile "$@"
}

_profiles_dir() {
    echo "$(dirname "$TMPFILE")/profiles"
}

@test "allowlist profile save creates a profile" {
    run hermit_allowlist_profile save test-profile
    [ "$status" -eq 0 ]
    [ -f "$(_profiles_dir)/test-profile" ]
    rm -rf "$(_profiles_dir)"
}

@test "allowlist profile load restores a profile" {
    hermit_allowlist_profile save test-profile
    echo "^extra\.com$" >> "$TMPFILE"
    hermit_allowlist_profile load test-profile
    ! grep -q "extra" "$TMPFILE"
    rm -rf "$(_profiles_dir)"
}

@test "allowlist profile list shows saved profiles" {
    hermit_allowlist_profile save test-profile
    run hermit_allowlist_profile list
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-profile"* ]]
    rm -rf "$(_profiles_dir)"
}

@test "allowlist profile rm deletes a profile" {
    hermit_allowlist_profile save test-profile
    run hermit_allowlist_profile rm test-profile
    [ "$status" -eq 0 ]
    [ ! -f "$(_profiles_dir)/test-profile" ]
    rm -rf "$(_profiles_dir)"
}

@test "allowlist profile load nonexistent exits non-zero" {
    run hermit_allowlist_profile load nonexistent
    [ "$status" -ne 0 ]
}

@test "allowlist profile rm nonexistent exits non-zero" {
    run hermit_allowlist_profile rm nonexistent
    [ "$status" -ne 0 ]
}
