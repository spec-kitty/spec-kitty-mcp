# Architecture

## Purpose

`spec-kitty-mcp` exposes the supported Spec Kitty external-orchestrator API as
MCP tools. It is a translation and safety boundary:

1. Accept a valid MCP request.
2. Validate the tool arguments and configured project boundary.
3. Construct a fixed `spec-kitty orchestrator-api` argument vector.
4. Run the command in the configured project root.
5. Parse the canonical JSON envelope.
6. Return structured MCP content without weakening the original result.

The server does not make workflow decisions. Spec Kitty owns mission state and
the validity of every requested operation.

## System boundary

```text
┌───────────────────────────────────────────────────────────────┐
│ MCP host                                                      │
│ - obtains user consent                                        │
│ - launches and shuts down the server                          │
└──────────────────────────────┬────────────────────────────────┘
                               │ newline-delimited JSON-RPC 2.0
┌──────────────────────────────▼────────────────────────────────┐
│ spec-kitty-mcp                                                │
│ - MCP lifecycle and tool schemas                              │
│ - input validation and safety defaults                        │
│ - subprocess timeout and output bounds                        │
│ - Spec Kitty envelope-to-tool-result mapping                  │
└──────────────────────────────┬────────────────────────────────┘
                               │ exec argv, fixed working directory
┌──────────────────────────────▼────────────────────────────────┐
│ spec-kitty orchestrator-api                                   │
│ - authoritative validation and state transitions              │
│ - dependency and lane guards                                  │
│ - policy audit metadata                                       │
│ - acceptance and merge preflights                             │
└───────────────────────────────────────────────────────────────┘
```

Anything below the orchestrator API boundary is private to Spec Kitty. The MCP
server must not depend on those implementation details.

## Process model

stdio is the default transport:

- The host starts one `spec-kitty-mcp` child process.
- The server reads one UTF-8 JSON-RPC message per stdin line.
- The server writes one UTF-8 JSON-RPC message per stdout line.
- Protocol messages contain no embedded newlines.
- All logs use stderr.
- Closing stdin requests graceful shutdown; the server then exits.

One process binds to one canonical project root. The root is supplied at
startup, resolved to an absolute path, and verified before initialization
completes. Per-tool arbitrary working directories are deliberately excluded.

`--http host:port` serves the same handler over localhost HTTP instead, with
read-only tools and a mandatory bearer credential. One process serves one
transport. The trust boundary differs between them: stdio inherits the trust of
the host that spawned it, while a socket is reachable by any local process, so
the HTTP path authenticates first and never exposes a mutating tool.

## Transport conformance

Transport choice is not allowed to change observable protocol behavior. The
ordered script in `src/conformance.zig` is the contract: framing, response
order, lifecycle gating, catalog gating, and JSON-RPC error codes. The stdio
driver in that file satisfies it today, and any further transport is expected
to supply its own driver and pass the same script unchanged.

Tool execution is not part of the script. It depends on the Spec Kitty binary
and is not transport-specific, so the smoke tests cover it instead.

## MCP lifecycle

The initial implementation supports:

1. `initialize` with protocol-version and capability negotiation
2. `notifications/initialized`
3. `ping`
4. `tools/list`
5. `tools/call`
6. shutdown by transport closure

The only advertised server capability in the first release is `tools`.
Resources, prompts, sampling, elicitation, and task-augmented tool calls are
out of scope until a concrete need justifies them.

The primary target is MCP revision `2025-11-25`. Supported revisions live in a
small explicit list so negotiation behavior is testable and older revisions
can be added deliberately.

## Spec Kitty contract negotiation

After validating the project root, startup invokes:

```text
spec-kitty orchestrator-api contract-version --provider-version <adapter-version>
```

Initialization fails if:

- the executable cannot be resolved;
- the command times out;
- stdout is not exactly one valid JSON object;
- the envelope reports `success: false`; or
- the provider and API versions are incompatible.

The negotiated API version controls which tools are advertised. For example,
`resolve-workspace` requires an API contract that provides it. A tool is never
listed merely because a similarly named command might exist.

## Internal modules

The foundation, MCP protocol, Spec Kitty subprocess, and complete planned tool
catalog exist today, including the explicitly destructive merge boundary.
Packaging, mutation integration coverage, and release automation remain.

### `main.zig`

- Parse startup configuration.
- Canonicalize and validate the project root.
- Resolve the Spec Kitty executable.
- Perform contract negotiation.
- Own buffered stdin, stdout, and stderr.
- Run the MCP message loop and graceful shutdown.

### `root.zig`

- Define the reusable package surface imported by the executable.
- Publish the adapter version.
- Ensure module tests are discovered from one test root.

### `cli.zig`

- Parse `--project-root` and `--spec-kitty-bin` without external dependencies.
- Reject missing, duplicate, unknown, and positional arguments.
- Publish stable help text and concise startup error descriptions.

### `project.zig`

- Open and canonicalize the configured project root.
- Require Git metadata and `.kittify/config.yaml`.
- Return an owned canonical path for the lifetime of the server process.

### `mcp.zig`

- Decode JSON-RPC requests and notifications.
- Track initialization state.
- Negotiate supported protocol revisions.
- Encode result and error responses.
- Reject invalid batches, methods, identifiers, and lifecycle ordering.

### `tools.zig`

- Publish tool names, descriptions, annotations, and JSON Schemas.
- Validate arguments before process execution.
- Map each public tool to one fixed command builder.
- Convert execution outcomes to MCP tool results.

### `spec_kitty.zig`

- Build argument vectors without shell interpolation.
- Execute the configured binary in the bound project root.
- Enforce timeouts and captured-output limits.
- Parse and minimally validate the Spec Kitty JSON envelope.
- Preserve correlation IDs and machine-readable error codes.

## Command execution

The adapter invokes an executable directly. User data occupies individual argv
entries and is never evaluated by a shell. Tool names do not become command
names dynamically; dispatch uses a compile-time catalog of known commands and
flags.

The child environment is inherited for compatibility with authenticated Git
operations, but environment contents are never included in tool output or
logs. Future environment filtering must preserve required Git and Spec Kitty
configuration and therefore needs its own compatibility tests.

Each invocation has:

- a configurable wall-clock timeout;
- bounded stdout and stderr capture;
- an explicit working directory;
- an exit-code record;
- JSON parsing independent of the exit code; and
- redaction-safe diagnostic logging.

## Result and error mapping

There are two error layers:

- **MCP protocol errors** cover malformed JSON-RPC, invalid parameters, unknown
  tools, lifecycle violations, and server defects.
- **Tool execution errors** cover Spec Kitty failures, timeouts, unavailable
  projects, and invalid Spec Kitty output. These return a normal MCP tool
  result with `isError: true` so an agent can inspect and correct the request.

When Spec Kitty returns a valid envelope, it remains the structured result,
including `contract_version`, `command`, `correlation_id`, `success`,
`error_code`, and `data`. The adapter does not translate a nonzero exit alone
into an opaque protocol failure.

## Mutation safety

- Read-only and mutating tools are described and annotated distinctly.
- Actor and required policy metadata stay explicit in tool arguments.
- Policy objects are serialized by the adapter, not accepted as raw JSON text.
- `merge_mission.push` defaults to `false`.
- The initial server does not expose `transition --force`.
- The adapter never retries a mutation unless the underlying operation has a
  documented idempotency guarantee.
- Timeouts report an indeterminate outcome when the child may have mutated
  state before termination; callers must query current state before retrying.

Tool annotations help hosts present confirmation, but they are not treated as
an authorization mechanism. The host and user retain control of tool approval.

## Test strategy

Most tests use a fake `spec-kitty` executable that records argv and emits
fixtures. This makes protocol and safety behavior deterministic without
mutating real projects.

Required test groups:

- JSON-RPC parsing, request IDs, notifications, and lifecycle ordering
- MCP version negotiation and rejection
- Tool catalog schemas and annotations
- Exact argv construction for every tool
- Shell-metacharacter and newline input cases
- Timeout and output-limit behavior
- Valid success and failure envelope mapping
- Invalid JSON, mixed stdout, missing fields, and exit-code combinations
- Project-root canonicalization and rejection
- End-to-end read-only smoke tests against an installed Spec Kitty CLI

Mutating integration tests use disposable repositories only.

## References

- [MCP specification, revision 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
