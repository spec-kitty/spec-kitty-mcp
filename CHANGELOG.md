# Changelog

## Unreleased

### Added

- A transport conformance script in `src/conformance.zig`: one ordered lifecycle
  script covering framing, response ordering, lifecycle gating, catalog gating,
  and JSON-RPC error codes, which both transports are held to
- An optional localhost HTTP transport behind `--http host:port`, serving
  `POST /mcp` with read-only tools and a mandatory bearer credential taken from
  `SPEC_KITTY_MCP_TOKEN` or `--token-file`, never from argv. Origin,
  `MCP-Protocol-Version`, media type, and the 1 MiB message cap are enforced,
  and a non-loopback bind requires `--insecure-bind`
- `tools.Access`, so a transport can serve a catalog filtered on `readOnlyHint`.
  A withheld tool answers exactly like a tool that does not exist

- Continuous integration on pull requests and pushes to `main`: `zig build check`
  plus a cross-compile of all four published targets
- A tag-triggered release workflow that packages and publishes the linux and macOS
  binaries with their `.sha256` sidecars, using the same
  `scripts/package-release.sh` as a local build
- A `workflow_dispatch` dry run that builds and uploads release artifacts without
  creating a release

### Changed

- `docs/releasing.md` now describes the automated release path. Pushing the version
  tag remains the human gate, and the two smoke suites remain a local pre-tag gate
  because they need a live installed `spec-kitty` executable.

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
