#!/usr/bin/env bats

load test_helper

@test "exec runs a command and returns output" {
    run "$HERMIT" exec echo hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "exec with no args shows usage error" {
    run "$HERMIT" exec
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"requires"* ]]
}

@test "entrypoint works without TTY (non-interactive)" {
    # Test real entrypoint behavior: no TTY, must not fail, claude --version
    # must work. Same compose file set hermit uses (not cwd-dependent) and the
    # helper's HERMIT_CONFIG_DIR, where claude.json already exists as a file
    # (a missing bind source would make Docker create a directory instead).
    run hermit_compose run --rm --no-deps -T claude-code --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+\ \(Claude\ Code\) ]]
}
