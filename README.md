# spec-kitty-mcp

A standalone Model Context Protocol (MCP) server for driving
[Spec Kitty](https://github.com/Priivacy-ai/spec-kitty) through its supported
`orchestrator-api` contract.

`spec-kitty-mcp` is intentionally an adapter, not a second implementation of
Spec Kitty. It gives MCP clients typed tools while leaving workflow rules,
state transitions, dependency checks, worktree paths, acceptance, and merge
preflights under Spec Kitty's control.

> **Status:** MCP core implemented. The Zig server negotiates the MCP lifecycle,
> handles newline-framed JSON-RPC over stdio, responds to ping, and publishes an
> empty tool catalog. Spec Kitty command execution is the next milestone.

## Why this exists

Spec Kitty already exposes a versioned, JSON-first API for external
orchestrators. MCP gives agents a standard way to discover and call that API.
This project connects the two without requiring a Spec Kitty fork, plugin, or
internal code change.

```text
MCP host
   │  JSON-RPC over stdio
   ▼
spec-kitty-mcp (Zig)
   │  argv-safe child processes
   ▼
spec-kitty orchestrator-api
   │
   ▼
Spec Kitty project and state machine
```

## Design principles

- **No Spec Kitty changes.** The server is installed and configured separately.
- **Supported boundary only.** It calls `spec-kitty orchestrator-api`; it does
  not scrape mission files, edit frontmatter, or mutate Git state directly.
- **Spec Kitty remains authoritative.** The adapter never invents transitions,
  bypasses guards, or interprets failed commands as success.
- **Safe process execution.** CLI arguments are passed as an argument vector,
  never interpolated into a shell command.
- **Machine-readable all the way down.** Successful and failed Spec Kitty JSON
  envelopes are preserved as structured MCP tool results.
- **Read-only first.** Mutation tools arrive only after protocol, subprocess,
  validation, timeout, and error-mapping tests are in place.
- **One project per server process.** A configured project root prevents an
  agent from silently reaching into an unrelated checkout.

## Planned tool surface

The first release maps the current Spec Kitty orchestrator contract to ten MCP
tools:

| MCP tool | Spec Kitty command | Effect |
|---|---|---|
| `spec_kitty_contract_version` | `contract-version` | Read-only |
| `spec_kitty_mission_state` | `mission-state` | Read-only |
| `spec_kitty_list_ready` | `list-ready` | Read-only |
| `spec_kitty_resolve_workspace` | `resolve-workspace` | Read-only |
| `spec_kitty_start_implementation` | `start-implementation` | Mutating |
| `spec_kitty_start_review` | `start-review` | Mutating |
| `spec_kitty_transition` | `transition` | Mutating |
| `spec_kitty_append_history` | `append-history` | Mutating |
| `spec_kitty_accept_mission` | `accept-mission` | Mutating |
| `spec_kitty_merge_mission` | `merge-mission` | Destructive potential |

See [Tool contract](docs/tool-contract.md) for the proposed MCP schemas and
safety treatment.

## Compatibility targets

- Zig `0.16.0` for initial development
- MCP protocol revision `2025-11-25`
- Spec Kitty orchestrator API contract `1.3.0`
- stdio transport for the first release

The server will negotiate both MCP and Spec Kitty contract versions at startup
and fail explicitly when no supported version overlaps. Compatibility is a
runtime check, not an assumption baked into a successful build.

## Safety model

Read-only tools may be called freely within the configured project root.
Mutation tools preserve Spec Kitty's policy metadata and guard failures.
`merge-mission` defaults to no push, and callers must explicitly request a
remote push. The first release will not expose Spec Kitty's `--force`
transition escape hatch.

The server writes protocol messages only to stdout. Diagnostics and child
process stderr go to stderr so logs cannot corrupt the MCP stream. Tool calls
have configurable timeouts and bounded captured output.

## Repository map

```text
docs/
├── architecture.md       Process, protocol, and trust boundaries
├── development-plan.md   Staged implementation and validation plan
└── tool-contract.md      Initial MCP tool catalog and error mapping
```

The implementation currently begins with:

```text
src/
├── main.zig              Process startup and stdout-safe entry point
├── root.zig              Reusable package surface
├── cli.zig               Startup option parsing
├── mcp.zig               JSON-RPC framing and MCP lifecycle
└── project.zig           Project-root validation and canonicalization
```

Tool-dispatch and Spec Kitty subprocess modules arrive in their corresponding
development milestones.

## Building and running

The project requires Zig 0.16.0:

```bash
zig build
zig build test
zig build check
```

Inspect the startup interface:

```bash
zig build run -- --help
zig build run -- --version
```

Validate an initialized Spec Kitty checkout:

```bash
zig build run -- --project-root /path/to/spec-kitty-project
```

Use a non-default Spec Kitty executable when needed:

```bash
zig build run -- \
  --project-root /path/to/spec-kitty-project \
  --spec-kitty-bin /path/to/spec-kitty
```

After validating configuration, the executable enters its MCP stdio loop. It
currently implements `initialize`, `notifications/initialized`, `ping`, and an
empty `tools/list`; EOF shuts the server down. Diagnostics remain on stderr and
stdout contains only newline-delimited JSON-RPC messages. Client configuration
examples will be added when the first useful tools land.

## Non-goals

- Reimplementing Spec Kitty's mission state machine
- Reading or editing `.kittify`, `kitty-specs`, worktree metadata, or Git refs
  behind Spec Kitty's back
- Providing a general-purpose shell execution tool
- Hiding policy metadata, actor identity, or guard failures from callers
- Owning agent scheduling or deciding which work package should run next
- Shipping HTTP transport before the local stdio server is solid

## Documentation

- [Architecture](docs/architecture.md)
- [Tool contract](docs/tool-contract.md)
- [Development plan](docs/development-plan.md)
- [MCP specification](https://modelcontextprotocol.io/specification/2025-11-25)
