#!/usr/bin/env bats

load test_helper

HERMIT="$COMPOSE_PROJECT_DIR/hermit"

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

# 1. allowlist list - prints entries from the allowlist file
@test "allowlist list prints entries" {
    run "$HERMIT" allowlist list --allowlist-file "$TMPFILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"api\.anthropic\.com"* ]]
    [[ "$output" == *"sentry\.io"* ]]
}

# 2. allowlist add example.com - appends exact match pattern
@test "allowlist add appends exact match pattern" {
    run "$HERMIT" allowlist add --allowlist-file "$TMPFILE" example.com
    [ "$status" -eq 0 ]
    grep -qF '^example\.com$' "$TMPFILE"
}

# 3. allowlist add --subdomains example.com - appends subdomain pattern
@test "allowlist add --subdomains appends subdomain pattern" {
    run "$HERMIT" allowlist add --subdomains --allowlist-file "$TMPFILE" example.com
    [ "$status" -eq 0 ]
    grep -qF '^(.+\.)?example\.com$' "$TMPFILE"
}

# 4. allowlist add duplicate - prints warning, no duplicate added
@test "allowlist add duplicate prints warning and does not duplicate" {
    "$HERMIT" allowlist add --allowlist-file "$TMPFILE" example.com
    count_before=$(grep -cF '^example\.com$' "$TMPFILE")
    run "$HERMIT" allowlist add --allowlist-file "$TMPFILE" example.com
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]] || [[ "$output" == *"duplicate"* ]]
    count_after=$(grep -cF '^example\.com$' "$TMPFILE")
    [ "$count_after" -eq "$count_before" ]
}

# 5. allowlist remove example.com - removes matching line
@test "allowlist remove deletes matching entry" {
    "$HERMIT" allowlist add --allowlist-file "$TMPFILE" example.com
    run "$HERMIT" allowlist remove --allowlist-file "$TMPFILE" example.com
    [ "$status" -eq 0 ]
    ! grep -qF 'example\.com' "$TMPFILE"
}

# 6. allowlist remove nonexistent.com - exits non-zero with error message
@test "allowlist remove nonexistent domain exits non-zero" {
    run "$HERMIT" allowlist remove --allowlist-file "$TMPFILE" nonexistent.com
    [ "$status" -ne 0 ]
    [ -n "$output" ]
}

# 7. allowlist check example.com - exits 0 when domain matches a pattern
@test "allowlist check exits 0 when domain matches" {
    run "$HERMIT" allowlist check --allowlist-file "$TMPFILE" api.anthropic.com
    [ "$status" -eq 0 ]
}

# 8. allowlist check evil.com - exits 1 when domain matches no pattern
@test "allowlist check exits 1 when domain does not match" {
    run "$HERMIT" allowlist check --allowlist-file "$TMPFILE" evil.com
    [ "$status" -eq 1 ]
}

# 9. allowlist (no subcommand) - defaults to list
@test "allowlist with no subcommand defaults to list" {
    run "$HERMIT" allowlist --allowlist-file "$TMPFILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"api\.anthropic\.com"* ]]
}

# 10. allowlist add (no domain) - exits non-zero with usage error
@test "allowlist add with no domain exits non-zero" {
    run "$HERMIT" allowlist add --allowlist-file "$TMPFILE"
    [ "$status" -ne 0 ]
    [ -n "$output" ]
}
