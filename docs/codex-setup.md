# Codex setup

Codex CLI, the Codex IDE extension, and the ChatGPT desktop app share the same
local MCP configuration. The configuration can live globally in
`~/.codex/config.toml` or in `.codex/config.toml` for a trusted project.

## Build the server

From this repository:

```bash
zig build -Doptimize=ReleaseSafe
```

The executable is written to `zig-out/bin/spec-kitty-mcp`. Use absolute paths
when registering it so the host does not depend on its launch directory.

## Register it with Codex CLI

Bind one server process to one initialized Spec Kitty project:

```bash
codex mcp add spec-kitty -- \
  /absolute/path/to/spec-kitty-mcp/zig-out/bin/spec-kitty-mcp \
  --project-root /absolute/path/to/spec-kitty-project
```

If `spec-kitty` is not available on the environment path inherited by Codex,
add its absolute executable path:

```bash
codex mcp add spec-kitty -- \
  /absolute/path/to/spec-kitty-mcp/zig-out/bin/spec-kitty-mcp \
  --project-root /absolute/path/to/spec-kitty-project \
  --spec-kitty-bin /absolute/path/to/spec-kitty
```

Run `codex mcp list` to inspect the saved entry. Start a new Codex session and
use `/mcp` to confirm that the server initialized and published its tools.

## Equivalent `config.toml`

For direct configuration:

```toml
[mcp_servers.spec_kitty]
command = "/absolute/path/to/spec-kitty-mcp/zig-out/bin/spec-kitty-mcp"
args = [
  "--project-root",
  "/absolute/path/to/spec-kitty-project",
]
startup_timeout_sec = 15
tool_timeout_sec = 60
default_tools_approval_mode = "writes"
```

The `writes` approval mode allows tools marked read-only to run without the
confirmation policy used for the five state-changing tools. MCP annotations
remain hints rather than authorization; Spec Kitty still enforces its own
contract, policy, actor ownership, and workflow guards.

## Verify the tool surface

Ask Codex to list the configured server's tools. With orchestrator contract
1.2.0 or newer, the catalog includes:

- `spec_kitty_contract_version`
- `spec_kitty_mission_state`
- `spec_kitty_list_ready`
- `spec_kitty_start_implementation`
- `spec_kitty_start_review`
- `spec_kitty_transition`
- `spec_kitty_append_history`
- `spec_kitty_accept_mission`
- `spec_kitty_merge_mission`
- `spec_kitty_resolve_workspace`

`spec_kitty_resolve_workspace` is omitted when the negotiated contract is
older than 1.2.0. Each server process is permanently bound to the project root
provided at launch; tool calls cannot select another checkout.

Codex should request confirmation before calling any state-changing tool under
the configuration above. Run-affecting transitions require a structured
`policy` object; review results and terminal evidence are also structured
objects rather than raw JSON strings. A successful implementation start may
return `no_op: true` when the same actor already owns an in-progress work
package. Failed transitions and acceptance guards remain visible through Spec
Kitty's original `error_code` and `correlation_id`.

`spec_kitty_merge_mission` is marked destructive and open-world because it
changes Git history and can optionally push. Omitting `push`, or passing
`push: false`, keeps `--push` out of the child argv. Treat `push: true` as a
separate explicit confirmation decision.

See the official [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp.md)
for shared-host configuration, approval modes, and other MCP settings.
