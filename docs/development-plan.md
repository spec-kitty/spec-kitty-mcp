# Development plan

Development proceeds from the protocol boundary inward. Each milestone leaves
the repository in a testable state and does not unlock mutations before their
safety behavior is covered.

## Milestone 0: contract and repository

- [x] Define the external-adapter boundary.
- [x] Record the initial MCP lifecycle and transport target.
- [x] Record the Spec Kitty orchestrator tool mapping.
- [x] Define safety defaults and non-goals.
- [x] Create and publish the standalone repository.

Exit condition: documentation consistently describes one implementable design.

## Milestone 1: Zig foundation

- [x] Add `build.zig` and `build.zig.zon` for Zig 0.16.0.
- [x] Add a minimal executable with strict stdout/stderr separation.
- [x] Parse startup options, including `--project-root` and optional
  `--spec-kitty-bin`.
- [x] Canonicalize and validate the project root.
- [x] Add formatting, unit-test, and build checks.

Exit condition: `zig build` and `zig build test` pass from a clean checkout.

## Milestone 2: MCP core

- [x] Implement newline-delimited UTF-8 JSON-RPC framing.
- [x] Implement request, response, error, and notification types.
- [x] Implement `initialize`, `notifications/initialized`, and `ping`.
- [x] Enforce lifecycle ordering and protocol-version negotiation.
- [x] Implement `tools/list` from a compile-time catalog.
- [x] Reject stdout logging in tests.

Exit condition: transcript fixtures from initialization through shutdown pass,
including malformed and unsupported requests.

## Milestone 3: Spec Kitty process boundary

- [x] Resolve the configured `spec-kitty` executable.
- [x] Execute argument vectors in the configured project root.
- [x] Add timeout and captured-output limits.
- [x] Parse and validate canonical Spec Kitty envelopes.
- [x] Negotiate the orchestrator contract at startup.
- [x] Build a fake CLI fixture for deterministic tests.

Exit condition: command construction, timeout behavior, output bounds, and all
success/failure envelope combinations are covered without touching a real
project.

## Milestone 4: read-only tools

- [x] Implement `spec_kitty_contract_version`.
- [x] Implement `spec_kitty_mission_state`.
- [x] Implement `spec_kitty_list_ready`.
- [x] Implement `spec_kitty_resolve_workspace` with capability gating.
- [x] Add a disposable-project integration smoke test.
- [x] Document configuration for at least one MCP host.

Exit condition: an MCP client can inspect a real Spec Kitty mission without
mutating it.

## Milestone 5: guarded mutations

- [x] Implement the structured policy schema and serialization.
- [x] Implement `spec_kitty_start_implementation`.
- [x] Implement `spec_kitty_start_review`.
- [x] Implement `spec_kitty_transition` without `force`.
- [x] Implement `spec_kitty_append_history`.
- [x] Implement `spec_kitty_accept_mission`.
- [x] Mark mutating tool annotations and document host confirmation behavior.
- [x] Add disposable-repository integration tests for every transition.

Exit condition: mutation requests preserve actor, policy, correlation, guard,
and failure information, with no adapter-side state edits.

## Milestone 6: merge boundary and release

- [x] Implement `spec_kitty_merge_mission` with `push: false` by default.
- [x] Test dirty-worktree, divergence, missing-work-package, and strategy
  failures in disposable repositories.
- [x] Add packaging and checksums for a standalone binary.
- [x] Add installation and upgrade documentation.
- [x] Add a clean-tree release-readiness check and release procedure.
- [x] Exercise the packaged server through an ephemeral live Codex host.
- [x] Publish the initial `v0.1.0` tagged release for macOS and Linux.

Exit condition: the release artifact can be installed, configured, exercised,
and removed without changing Spec Kitty itself.

## Deferred ideas

These are deliberately outside the initial release:

- Streamable HTTP transport and its authentication model (design settled below)
- MCP resources for mission snapshots
- Task-augmented long-running merge operations
- Dynamic multi-project routing in one server process
- Exposing forced transitions
- Automatic mutation retries
- Agent scheduling or mission sequencing

Each requires a separate design decision because it widens the trust boundary.

### Streamable HTTP transport

The authentication decision is settled in
[#13](https://github.com/spec-kitty/spec-kitty-mcp/issues/13): a first
localhost phase serves read-only tools behind mandatory bearer authentication.
Shipping it is still deferred. These are the conditions.

- Default bind `127.0.0.1`. A wider bind needs an explicit insecure flag.
- The token comes from an environment variable or a `0600` token file, never
  from argv. `/proc/<pid>/cmdline` is readable by other local processes, which
  is the exact threat the token exists to stop.
- Token comparison hashes both sides to a fixed-size digest and compares in
  constant time, so token length cannot leak through an early return.
- The served catalog is filtered on `readOnlyHint`, so `tools/list` and
  `tools/call` share one source of truth and cannot drift. Mutation opt-in, if
  it ever arrives, is a per-tool allowlist and not one global switch.
- `Origin` validation returns 403 and `MCP-Protocol-Version` enforcement
  returns 400.
- The 1 MiB `max_message_bytes` cap is enforced by rejecting on
  `Content-Length` before the body is read.
- TLS terminates at a reverse proxy. No cleartext remote exposure.
- `Mcp-Session-Id` belongs to a later GET or SSE phase.

Prerequisite, landed: the transport conformance script in
`src/conformance.zig`, so a listener has a defined target to pass before it is
written.

OAuth 2.1 authorization stays parked until a remote consumer asks for it.
