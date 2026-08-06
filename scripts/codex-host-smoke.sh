#!/bin/sh
set -eu

usage() {
    echo "usage: $0 <spec-kitty-project-root> [server-binary]" >&2
    exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
project_root=$(CDPATH= cd -- "$1" && pwd)
server_binary=${2:-$repo_root/zig-out/bin/spec-kitty-mcp}

case "$project_root" in
    *\"*|*\\*)
        echo "host smoke: project paths containing quotes or backslashes are unsupported" >&2
        exit 2
        ;;
esac
case "$server_binary" in
    *\"*|*\\*)
        echo "host smoke: binary paths containing quotes or backslashes are unsupported" >&2
        exit 2
        ;;
esac

command -v codex >/dev/null 2>&1 || {
    echo "host smoke: codex is not available on PATH" >&2
    exit 1
}
command -v spec-kitty >/dev/null 2>&1 || {
    echo "host smoke: spec-kitty is not available on PATH" >&2
    exit 1
}
[ -x "$server_binary" ] || {
    echo "host smoke: server binary is not executable: $server_binary" >&2
    exit 1
}
[ -d "$project_root/.git" ] || {
    echo "host smoke: project root has no .git directory: $project_root" >&2
    exit 1
}
[ -f "$project_root/.kittify/config.yaml" ] || {
    echo "host smoke: project root has no .kittify/config.yaml: $project_root" >&2
    exit 1
}

events_file=$(mktemp "${TMPDIR:-/tmp}/spec-kitty-mcp-codex-host.XXXXXX")
cleanup() {
    rm -f -- "$events_file"
}
trap cleanup EXIT HUP INT TERM

codex exec \
    --ephemeral \
    --ignore-user-config \
    --ignore-rules \
    --sandbox read-only \
    --json \
    -c "mcp_servers.spec_kitty_mcp.command=\"$server_binary\"" \
    -c "mcp_servers.spec_kitty_mcp.args=[\"--project-root\",\"$project_root\"]" \
    -c 'mcp_servers.spec_kitty_mcp.required=true' \
    -c 'mcp_servers.spec_kitty_mcp.enabled_tools=["spec_kitty_contract_version"]' \
    -c 'mcp_servers.spec_kitty_mcp.default_tools_approval_mode="auto"' \
    'Use the spec_kitty_contract_version MCP tool exactly once. Do not run shell commands or inspect files. Report only the returned api_version and min_supported_provider_version.' \
    > "$events_file"

grep -F '"type":"mcp_tool_call"' "$events_file" >/dev/null
grep -F '"server":"spec_kitty_mcp"' "$events_file" >/dev/null
grep -F '"tool":"spec_kitty_contract_version"' "$events_file" >/dev/null
grep -F '"status":"completed"' "$events_file" >/dev/null
grep -F '"success":true' "$events_file" >/dev/null
grep -F '"api_version"' "$events_file" >/dev/null
grep -F '"min_supported_provider_version"' "$events_file" >/dev/null

call_count=$(grep -Ec '"type":"item.completed".*"type":"mcp_tool_call","server":"spec_kitty_mcp","tool":"spec_kitty_contract_version"' "$events_file")
[ "$call_count" -eq 1 ] || {
    echo "host smoke: expected one completed contract tool call, found $call_count" >&2
    exit 1
}

echo "host smoke: Codex launched spec-kitty-mcp and completed a real contract tool call"
