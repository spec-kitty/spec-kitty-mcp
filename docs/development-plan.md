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
- [ ] Implement `spec_kitty_resolve_workspace` with capability gating.
- [ ] Add a disposable-project integration smoke test.
- [ ] Document configuration for at least one MCP host.

Exit condition: an MCP client can inspect a real Spec Kitty mission without
mutating it.

## Milestone 5: guarded mutations

- [ ] Implement the structured policy schema and serialization.
- [ ] Implement `spec_kitty_start_implementation`.
- [ ] Implement `spec_kitty_start_review`.
- [ ] Implement `spec_kitty_transition` without `force`.
- [ ] Implement `spec_kitty_append_history`.
- [ ] Implement `spec_kitty_accept_mission`.
- [ ] Mark mutating tool annotations and document host confirmation behavior.
- [ ] Add disposable-repository integration tests for every transition.

Exit condition: mutation requests preserve actor, policy, correlation, guard,
and failure information, with no adapter-side state edits.

## Milestone 6: merge boundary and release

- [ ] Implement `spec_kitty_merge_mission` with `push: false` by default.
- [ ] Test dirty-worktree, divergence, missing-work-package, and strategy
  failures in disposable repositories.
- [ ] Add packaging and checksums for a standalone binary.
- [ ] Add installation and upgrade documentation.
- [ ] Publish an initial tagged release.

Exit condition: the release artifact can be installed, configured, exercised,
and removed without changing Spec Kitty itself.

## Deferred ideas

These are deliberately outside the initial release:

- Streamable HTTP transport and its authentication model
- MCP resources for mission snapshots
- Task-augmented long-running merge operations
- Dynamic multi-project routing in one server process
- Exposing forced transitions
- Automatic mutation retries
- Agent scheduling or mission sequencing

Each requires a separate design decision because it widens the trust boundary.
