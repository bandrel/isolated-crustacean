#!/usr/bin/env bats

load test_helper

@test "internal network has explicit name" {
    run docker compose -f "$COMPOSE_PROJECT_DIR/docker-compose.yml" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: ic-internal"* ]]
}

@test "hermit status works with no MCP servers enabled" {
    run "$HERMIT" status
    [ "$status" -eq 0 ]
}

@test "all templates have required x-mcp fields" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        for field in name description transport port path; do
            run yq -e ".x-mcp.$field" "$tmpl"
            [ "$status" -eq 0 ] || {
                echo "Missing x-mcp.$field in $(basename "$tmpl")"
                return 1
            }
        done
    done
}

@test "all templates define a service named mcp-<name>" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        name=$(yq -r '.x-mcp.name' "$tmpl")
        run grep "  mcp-${name}:" "$tmpl"
        [ "$status" -eq 0 ] || {
            echo "Service mcp-${name} not found in $(basename "$tmpl")"
            return 1
        }
    done
}

_test_vol_prefix="hermittest-mcp"
_hermit_workspace_bak=""
_proxy_rebuilt=""

setup() {
    cp "$ALLOWLIST_FILE" "$ALLOWLIST_FILE.bak"
    _test_name="${_test_vol_prefix}-$$-${BATS_TEST_NUMBER}"
    if [[ -f "$COMPOSE_PROJECT_DIR/.hermit-workspace" ]]; then
        _hermit_workspace_bak="$(cat "$COMPOSE_PROJECT_DIR/.hermit-workspace")"
    else
        _hermit_workspace_bak=""
    fi
    _proxy_rebuilt=""
}

# Rebuild tinyproxy (the allowlist is baked into its image) and bring it up
# together with the given MCP services, using hermit's compose file set.
# --wait blocks on the MCP healthchecks, like hermit's mcp_services_up.
# Fails the test immediately (with the compose output shown) on any error.
bring_up_mcp() {
    _proxy_rebuilt=1
    hermit_compose build --quiet tinyproxy "$@" || {
        echo "bring_up_mcp: build failed for: tinyproxy $*"
        return 1
    }
    hermit_compose up -d --wait --wait-timeout 90 tinyproxy "$@" || {
        echo "bring_up_mcp: up --wait failed for: tinyproxy $*"
        hermit_compose ps
        hermit_compose logs --tail 20 "$@"
        return 1
    }
}

teardown() {
    # Remove MCP containers while their compose files are still enabled
    local _f _name
    for _f in "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml; do
        [[ -e "$_f" ]] || continue
        _name="$(yq -r '.x-mcp.name' "$_f")"
        hermit_compose rm -sf "mcp-${_name}" >/dev/null 2>&1 || true
    done
    mv "$ALLOWLIST_FILE.bak" "$ALLOWLIST_FILE"
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/enabled/*.yml
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/templates/test-hyphen.yml
    rm -f "$COMPOSE_PROJECT_DIR"/mcp/.runtime/workspace.yml
    if [[ -n "$_hermit_workspace_bak" ]]; then
        echo "$_hermit_workspace_bak" > "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    else
        rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    fi
    docker volume ls --filter "name=^isolated-crustacean-${_test_vol_prefix}" -q | xargs -r docker volume rm 2>/dev/null || true
    # Put the proxy back on the original allowlist for later suites
    if [[ -n "$_proxy_rebuilt" ]]; then
        hermit_compose build tinyproxy >/dev/null 2>&1
        hermit_compose up -d tinyproxy >/dev/null 2>&1
    fi
}

@test "all templates reference the ic-internal network" {
    for tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        [[ "$(basename "$tmpl")" == ".gitkeep" ]] && continue
        run grep "name: ic-internal" "$tmpl"
        [ "$status" -eq 0 ] || {
            echo "Missing ic-internal network in $(basename "$tmpl")"
            return 1
        }
    done
}

@test "mcp add copies template to enabled" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [ -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}

@test "mcp add adds allowlist entry" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    grep -q '^\^mcp-filesystem\$$' "$ALLOWLIST_FILE"
}

@test "mcp add updates claude.json mcpServers" {
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers.filesystem.url' "$HERMIT_CONFIG_DIR/claude.json"
    [ "$output" = "http://mcp-filesystem:3000/mcp" ]
    # Claude Code skips url-only entries; Streamable HTTP must be type "http"
    run jq -r '.mcpServers.filesystem.type' "$HERMIT_CONFIG_DIR/claude.json"
    [ "$output" = "http" ]
}

@test "mcp add fails for nonexistent template" {
    run "$HERMIT" mcp add nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "mcp add warns on duplicate" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled"* ]]
}

@test "mcp rm removes enabled file" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    [ ! -f "$COMPOSE_PROJECT_DIR/mcp/enabled/filesystem.yml" ]
}

@test "mcp rm removes allowlist entry" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    ! grep -q '^\^mcp-filesystem\$$' "$ALLOWLIST_FILE"
}

@test "mcp rm removes claude.json entry" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp rm filesystem
    [ "$status" -eq 0 ]
    run jq -r '.mcpServers.filesystem // "null"' "$HERMIT_CONFIG_DIR/claude.json"
    [ "$output" = "null" ]
}

@test "mcp rm leaves the allowlist world-readable (tinyproxy runs as nobody)" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp rm filesystem
    # mktemp+mv used to leave 0600, which tinyproxy could not read after COPY
    _mode="$(stat -f '%Lp' "$ALLOWLIST_FILE" 2>/dev/null || stat -c '%a' "$ALLOWLIST_FILE")"
    [ "$_mode" = "644" ]
}

@test "mcp rm fails for non-enabled server" {
    run "$HERMIT" mcp rm filesystem
    [ "$status" -ne 0 ]
    [[ "$output" == *"not enabled"* ]]
}

@test "mcp list shows available templates" {
    run "$HERMIT" mcp list
    [ "$status" -eq 0 ]
    [[ "$output" == *"filesystem"* ]]
    [[ "$output" == *"github"* ]]
}

@test "mcp list shows enabled status" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    run "$HERMIT" mcp list
    [ "$status" -eq 0 ]
    [[ "$output" == *"filesystem"* ]]
    [[ "$output" == *"enabled"* ]]
}

@test "mcp status runs without error" {
    run "$HERMIT" mcp status
    [ "$status" -eq 0 ]
}

@test "mcp restart runs without error when no servers enabled" {
    run "$HERMIT" mcp restart
    [ "$status" -eq 0 ]
}

@test "doctor checks MCP allowlist consistency" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    # Remove allowlist entry manually to create inconsistency
    _tmpfile="$(mktemp)"
    grep -v 'mcp-filesystem' "$ALLOWLIST_FILE" > "$_tmpfile" || true
    mv "$_tmpfile" "$ALLOWLIST_FILE"
    run "$HERMIT" doctor
    # Doctor should report FAIL on the mcp-filesystem allowlist line (anchor to line start)
    grep -Eq '^MCP allowlist: mcp-filesystem[^[:cntrl:]]*FAIL' <<<"$output"
    # Doctor should exit non-zero when there's an inconsistency
    [ "$status" -ne 0 ]
}

@test "enabled MCP server is reachable through proxy" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace
    bring_up_mcp mcp-filesystem
    run mcp_initialize_via_proxy filesystem 3000
    [ "$status" -eq 0 ]
    # Successful JSON-RPC result (not an error object) carrying serverInfo
    [[ "$output" == *'"result"'* ]]
    [[ "$output" == *'"serverInfo"'* ]]
    [[ "$output" == *'"secure-filesystem-server"'* ]]
    [[ "$output" != *'"error"'* ]]
}

@test "every shipped MCP template initializes through proxy" {
    local _tmpl _name _port
    for _tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        _name="$(yq -r '.x-mcp.name' "$_tmpl")"
        _port="$(yq -r '.x-mcp.port' "$_tmpl")"
        HERMIT_NO_REBUILD=1 "$HERMIT" mcp add "$_name"
    done
    "$HERMIT" mcp sync-workspace
    local -a _svcs=()
    for _tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        _svcs+=("mcp-$(yq -r '.x-mcp.name' "$_tmpl")")
    done
    bring_up_mcp "${_svcs[@]}"
    for _tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        _name="$(yq -r '.x-mcp.name' "$_tmpl")"
        _port="$(yq -r '.x-mcp.port' "$_tmpl")"
        run mcp_initialize_via_proxy "$_name" "$_port"
        [ "$status" -eq 0 ] || { echo "initialize failed for $_name"; return 1; }
        [[ "$output" == *'"serverInfo"'* ]] || { echo "no serverInfo from $_name: $output"; return 1; }
        [[ "$output" != *'"error"'* ]] || { echo "error from $_name: $output"; return 1; }
    done
}

@test "MCP templates with build: have a repo-root-relative Dockerfile context" {
    # compose resolves relative build contexts against the project directory
    # (the first -f file's dir = repo root), not the template's own directory
    local _tmpl _ctx
    for _tmpl in "$COMPOSE_PROJECT_DIR"/mcp/templates/*.yml; do
        _ctx="$(yq -r '.services[].build // ""' "$_tmpl")"
        [[ -n "$_ctx" ]] || continue
        [[ "$_ctx" == ./mcp/images/* ]] || {
            echo "Build context in $(basename "$_tmpl") must be ./mcp/images/<name>, got: $_ctx"
            return 1
        }
        [ -f "$COMPOSE_PROJECT_DIR/$_ctx/Dockerfile" ] || {
            echo "Missing Dockerfile for $(basename "$_tmpl"): $_ctx"
            return 1
        }
    done
}

@test "postgres template is not shipped (proxy cannot reach a database)" {
    [ ! -e "$COMPOSE_PROJECT_DIR/mcp/templates/postgres.yml" ]
    run "$HERMIT" mcp list
    [ "$status" -eq 0 ]
    [[ "$output" != *"postgres"* ]]
}

@test "mcp add warns when a template's required env var is unset" {
    GITHUB_PERSONAL_ACCESS_TOKEN= HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add github
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: GITHUB_PERSONAL_ACCESS_TOKEN is not set"* ]]
}

@test "mcp sync-workspace writes a git-ignored runtime override" {
    run "$HERMIT" mcp sync-workspace
    [ "$status" -eq 0 ]
    [ -f "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml" ]
    git -C "$COMPOSE_PROJECT_DIR" check-ignore -q mcp/.runtime/workspace.yml
    [ "$(yq -r '.x-hermit.workspace_mode' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "volume" ]
}

@test "compose config: default workspace agrees between claude-code and MCP /data" {
    rm -f "$COMPOSE_PROJECT_DIR/.hermit-workspace"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace
    [ "$(workspace_mount_source claude-code /home/node/workspace)" = "ic-workspace" ]
    [ "$(workspace_mount_source mcp-filesystem /data)" = "ic-workspace" ]
}

@test "compose config: named workspace agrees between claude-code and MCP /data" {
    "$HERMIT" workspace create "$_test_name"
    "$HERMIT" workspace switch "$_test_name"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add git
    "$HERMIT" mcp sync-workspace
    _expected="isolated-crustacean-${_test_name}"
    [ "$(workspace_mount_source claude-code /home/node/workspace)" = "$_expected" ]
    [ "$(workspace_mount_source mcp-filesystem /data)" = "$_expected" ]
    [ "$(workspace_mount_source mcp-git /data)" = "$_expected" ]
}

@test "compose config: --mount path agrees between claude-code and MCP /data" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace --mount "$BATS_TEST_TMPDIR"
    _expected="$(cd "$BATS_TEST_TMPDIR" && pwd)"
    [ "$(workspace_mount_source claude-code /home/node/workspace)" = "$_expected" ]
    [ "$(workspace_mount_source mcp-filesystem /data)" = "$_expected" ]
    # Both must be bind mounts, not the named volume
    run hermit_compose config --format json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.services["claude-code"].volumes[] | select(.target=="/home/node/workspace") | .type' <<<"$output")" = "bind" ]
    [ "$(jq -r '.services["mcp-filesystem"].volumes[] | select(.target=="/data") | .type' <<<"$output")" = "bind" ]
}

@test "compose config: claude-code NO_PROXY lists enabled MCP hosts" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add git
    "$HERMIT" mcp sync-workspace
    run hermit_compose config --format json
    [ "$status" -eq 0 ]
    _no_proxy="$(jq -r '.services["claude-code"].environment.NO_PROXY' <<<"$output")"
    [[ ",$_no_proxy," == *",mcp-filesystem,"* ]]
    [[ ",$_no_proxy," == *",mcp-git,"* ]]
    # Proxy vars themselves must remain for everything else
    [ "$(jq -r '.services["claude-code"].environment.HTTPS_PROXY' <<<"$output")" = "http://tinyproxy:8888" ]
}

@test "claude mcp list inside claude-code reports the enabled server as Connected" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace
    bring_up_mcp mcp-filesystem
    # Real Claude Code client, real registration in the isolated claude.json.
    # tinyproxy cannot relay Claude's keep-alive MCP session (see hermit's
    # write_workspace_override), so this only passes with NO_PROXY in place.
    run hermit_compose run --rm --no-deps -T --entrypoint bash claude-code \
        -c 'timeout 90 claude mcp list 2>&1'
    [ "$status" -eq 0 ]
    grep -Eq '^filesystem: http://mcp-filesystem:3000/mcp \(HTTP\) - .*Connected' <<<"$output"
    [[ "$output" != *"Failed to connect"* ]]
}

@test "stale bind-mode override after mcp rm does not break hermit status" {
    # Reviewer repro: bind override references mcp-filesystem, then the
    # service is disabled without a rebuild. Every compose_cmd used to die
    # with 'service "mcp-filesystem" has neither an image nor a build context'.
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace --mount "$BATS_TEST_TMPDIR"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp rm filesystem
    run "$HERMIT" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"neither an image nor a build context"* ]]
    # The override must still exist and still pin the bind path (not reset)
    [ -f "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml" ]
    [ "$(yq -r '.x-hermit.workspace_mode' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "bind" ]
    run yq -r '.services | keys | .[]' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml"
    [[ "$output" != *"mcp-filesystem"* ]]
    run "$HERMIT" doctor
    [[ "$output" != *"neither an image nor a build context"* ]]
}

@test "stale override after manual delete of an enabled file does not break compose_cmd" {
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add git
    "$HERMIT" mcp sync-workspace --mount "$BATS_TEST_TMPDIR"
    rm "$COMPOSE_PROJECT_DIR/mcp/enabled/git.yml"
    run "$HERMIT" status
    [ "$status" -eq 0 ]
    [[ "$output" != *"neither an image nor a build context"* ]]
    # Pruned to what is still enabled; NO_PROXY follows suit
    run yq -r '.services | keys | .[]' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml"
    [[ "$output" == *"mcp-filesystem"* ]]
    [[ "$output" != *"mcp-git"* ]]
    [ "$(yq -r '.services["claude-code"].environment.NO_PROXY' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "mcp-filesystem" ]
    _expected="$(cd "$BATS_TEST_TMPDIR" && pwd)"
    [ "$(workspace_mount_source mcp-filesystem /data)" = "$_expected" ]
}

@test "mcp add/rm rewrite the override even with HERMIT_NO_REBUILD=1" {
    "$HERMIT" mcp sync-workspace
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    [ "$(yq -r '.services["claude-code"].environment.NO_PROXY' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "mcp-filesystem" ]
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp rm filesystem
    [ "$(yq -r '.services["claude-code"].environment.NO_PROXY' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "" ]
}

@test "--mount path containing \$ is not interpolated by compose" {
    # Under /tmp (not BATS_TEST_TMPDIR) so Docker Desktop can bind-mount it
    _base="$(mktemp -d /tmp/hermit-dollar.XXXXXX)"
    _dir="$_base/my mount \$HOME dir"
    mkdir -p "$_dir"
    echo marker > "$_dir/.hermit-dollar-marker"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace --mount "$_dir"
    _expected="$(cd "$_dir" && pwd)"
    # `compose config` re-escapes a literal $ as $$ in its own output, so
    # unescape before comparing. An interpolated path would contain $HOME's
    # value instead and never match.
    _cc="$(workspace_mount_source claude-code /home/node/workspace | sed 's/\$\$/$/g')"
    _fs="$(workspace_mount_source mcp-filesystem /data | sed 's/\$\$/$/g')"
    [ "$_cc" = "$_expected" ]
    [ "$_fs" = "$_expected" ]
    [[ "$_cc" != *"$HOME"* ]]
    # The recorded source round-trips through current_workspace_source
    # (exercised by a NO_REBUILD rewrite adding a second service)
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add git
    [ "$(workspace_mount_source mcp-git /data | sed 's/\$\$/$/g')" = "$_expected" ]
    # Real container proof: the literal directory is what gets mounted
    run hermit_compose run --rm --no-deps -T --entrypoint bash claude-code \
        -c 'cat /home/node/workspace/.hermit-dollar-marker'
    rm -rf "$_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker"* ]]
}

@test "--mount path containing ' and \" is written as a valid YAML scalar" {
    _base="$(mktemp -d /tmp/hermit-quote.XXXXXX)"
    _dir="$_base/it's a \"quoted\" dir"
    mkdir -p "$_dir"
    echo marker > "$_dir/.hermit-quote-marker"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    run "$HERMIT" mcp sync-workspace --mount "$_dir"
    [ "$status" -eq 0 ]
    _expected="$(cd "$_dir" && pwd)"
    # The file must parse, and yq must give back the exact path
    [ "$(yq -r '.x-hermit.workspace_source' "$COMPOSE_PROJECT_DIR/mcp/.runtime/workspace.yml")" = "$_expected" ]
    [ "$(workspace_mount_source claude-code /home/node/workspace)" = "$_expected" ]
    [ "$(workspace_mount_source mcp-filesystem /data)" = "$_expected" ]
    # Round-trips through current_workspace_source on a rewrite
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add git
    [ "$(workspace_mount_source mcp-git /data)" = "$_expected" ]
    run hermit_compose run --rm --no-deps -T --entrypoint bash claude-code \
        -c 'cat /home/node/workspace/.hermit-quote-marker'
    rm -rf "$_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker"* ]]
}

@test "mcp sync-workspace --mount with nonexistent path exits non-zero" {
    run "$HERMIT" mcp sync-workspace --mount /nonexistent/path/xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "filesystem MCP server sees files claude-code writes to a named workspace" {
    "$HERMIT" workspace create "$_test_name"
    "$HERMIT" workspace switch "$_test_name"
    HERMIT_NO_REBUILD=1 "$HERMIT" mcp add filesystem
    "$HERMIT" mcp sync-workspace
    bring_up_mcp mcp-filesystem
    # Write through the claude-code container using hermit's compose file set
    # (so it gets the same override the MCP service got)
    hermit_compose run --rm --no-deps -T --entrypoint bash claude-code \
        -c 'echo "hermit-e2e-$$" > /home/node/workspace/.hermit-e2e && cat /home/node/workspace/.hermit-e2e' >/dev/null 2>&1
    _body='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_text_file","arguments":{"path":"/data/.hermit-e2e"}}}'
    run run_in_container "curl -s --max-time 30 -X POST \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '$_body' http://mcp-filesystem:3000/mcp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hermit-e2e-"* ]]
    [[ "$output" != *'"isError":true'* ]]
    # And the file really is on the named volume, not ic-workspace
    run docker run --rm -v "isolated-crustacean-${_test_name}:/w" ic-mcp-filesystem cat /w/.hermit-e2e
    [ "$status" -eq 0 ]
    [[ "$output" == *"hermit-e2e-"* ]]
}

@test "docker compose config uses HERMIT_CONFIG_DIR for mounts" {
    run docker compose -f "$COMPOSE_PROJECT_DIR/docker-compose.yml" config
    [ "$status" -eq 0 ]
    # Should contain HERMIT_CONFIG_DIR paths in long-form volume source
    grep -q "source: ${HERMIT_CONFIG_DIR}/claude" <<<"$output"
    # Should NOT contain the host's HOME directory as mount source (long-form)
    ! grep -q "source: ${HOME}/.claude" <<<"$output"
}

@test "mcp add does not modify host ~/.claude.json" {
    _host_json="$HOME/.claude.json"
    # Skip if host's ~/.claude.json doesn't exist
    [[ -f "$_host_json" ]] || skip "host ~/.claude.json not present"

    # Capture checksum before
    _checksum_before="$(shasum -a 256 "$_host_json" | awk '{print $1}')"

    # Run mcp add with HERMIT_NO_REBUILD
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add filesystem
    [ "$status" -eq 0 ]

    # Checksum should be identical (host file untouched)
    _checksum_after="$(shasum -a 256 "$_host_json" | awk '{print $1}')"
    [ "$_checksum_before" = "$_checksum_after" ]
}

@test "doctor MCP config check works for hyphenated server names" {
    # Create a temporary template with a hyphenated name
    _temp_tmpl="$COMPOSE_PROJECT_DIR/mcp/templates/test-hyphen.yml"
    cat > "$_temp_tmpl" <<'EOF'
services:
  mcp-test-hyphen:
    image: alpine:3.21
    networks:
      - ic-internal

x-mcp:
  name: test-hyphen
  description: Test template with hyphenated name
  transport: stdio
  port: 3000
  path: /mcp

networks:
  ic-internal:
    name: ic-internal
    external: true
EOF

    # Add the MCP server
    HERMIT_NO_REBUILD=1 run "$HERMIT" mcp add test-hyphen
    [ "$status" -eq 0 ]

    # Doctor should handle hyphenated names correctly
    run "$HERMIT" doctor
    # Should check the hyphenated server name without error
    [ "$status" -eq 0 ]
    [[ "$output" == *"MCP allowlist: mcp-test-hyphen"* ]]
    [[ "$output" == *"MCP config: test-hyphen"* ]]
}
