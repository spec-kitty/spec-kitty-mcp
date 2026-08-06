# Changelog

## 0.1.0 - 2026-08-06

Initial release of the standalone Zig MCP adapter for Spec Kitty.

### Included

- MCP `2025-11-25` stdio lifecycle and JSON-RPC framing
- Ten tools spanning contract negotiation, mission queries, guarded workflow
  mutations, acceptance, and merge
- Spec Kitty orchestrator contract `1.3.0` negotiation at startup
- Structured policy, evidence, correlation, and error-envelope preservation
- Project-root isolation, bounded child output, timeouts, and argv-safe process
  execution
- Mutation and merge safety annotations, including destructive/open-world hints
  for remote-capable merge operations
- Disposable read-only, mutation-lifecycle, and merge-failure integration tests
- Live Codex host validation against the packaged Linux x86_64 binary

### Release assets

- `aarch64-macos`
- `x86_64-macos`
- `aarch64-linux-musl` (statically linked)
- `x86_64-linux-musl` (statically linked)

Each binary has a matching `.sha256` sidecar. The macOS artifacts are
cross-compiled and format-verified; they are not code-signed or notarized.

### Requirements

- A compatible installed `spec-kitty` executable
- An initialized Git-backed Spec Kitty project
- One MCP server process per bound project root
