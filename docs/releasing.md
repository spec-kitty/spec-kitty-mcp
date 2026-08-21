# Release procedure

Publishing a release is an intentional human gate. Verification and packaging are
automated; deciding to release is not. Pushing a version tag is the decision, and
CI does everything after it.

## Continuous checks

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on every pull
request and every push to `main`:

- `zig build check` (formatting, compile, unit tests)
- a cross-compile of all four published targets

The two smoke suites (`smoke-read-only`, `smoke-mutations`) are not in CI. They
require a live installed `spec-kitty` executable and a real Git-backed project, so
they remain a local pre-tag gate. Run them before every release.

## Prepare

1. Update `.version` in `build.zig.zon` to the intended release version.
2. Add a `CHANGELOG.md` section whose heading starts with that exact version, for
   example `## 0.2.0 - 2026-09-01`. The release workflow uses this section as the
   release notes and fails if it is missing.
3. Update compatibility notes and installation examples when their values change.
4. Commit and push those changes to `main` through a reviewed pull request.
5. Confirm the local branch is clean and synchronized with `origin/main`.

## Verify locally

Run the full unit, installed-CLI, mutation, packaging, version, and checksum
checks, which include the smoke suites CI cannot run:

```bash
./scripts/release-check.sh 0.2.0 x86_64-linux-musl
```

This is the gate that CI does not replace. The release workflow refuses a version
that differs from `build.zig.zon`, but only this command exercises the live
orchestrator contract.

## Dry run the release build

Before tagging, run the **Release** workflow manually from the Actions tab with
the target version as its input. A `workflow_dispatch` run builds and packages all
four targets and uploads them as workflow artifacts, then stops. It does not create
a release, so the tag stays unused and the artifacts can be downloaded and
inspected.

## Tag

Inspect the exact commit before creating the tag:

```bash
git status --short --branch
git log -1 --oneline
```

After explicit release approval, create an annotated tag and push only that tag:

```bash
git tag -a v0.2.0 -m "spec-kitty-mcp 0.2.0"
git push origin v0.2.0
```

Do not move or reuse a published version tag. Correct a release with a new patch
version.

## What CI publishes

The tag push triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. confirms the tag version matches `build.zig.zon`
2. runs `zig build check`
3. packages each target through `scripts/package-release.sh`, the same script used
   locally, so CI and laptop artifacts are produced identically
4. confirms the built binary reports the expected version
5. re-verifies every `.sha256` sidecar after artifact transfer
6. creates the GitHub release from the `CHANGELOG.md` section, attaching all four
   binaries and their sidecars

A version containing a hyphen, such as `0.2.0-rc.1`, is published as a prerelease.

Published targets:

| Target | Notes |
| --- | --- |
| `x86_64-linux-musl` | statically linked |
| `aarch64-linux-musl` | statically linked |
| `x86_64-macos` | cross-compiled, unsigned |
| `aarch64-macos` | cross-compiled, unsigned |

All targets are cross-compiled from a single Linux runner. The macOS binaries are
not code-signed or notarized, so a first local run needs a Gatekeeper override.
Adding a target means adding it to the matrix in both workflows.

The builds are reproducible: rebuilding a tagged commit at the same version yields
binaries with the same checksums as the published assets.

## After publishing

Verify that the public asset URLs and the commands in
[Installation and upgrades](installation.md) work from a fresh temporary
directory before announcing the release.

## Abort or roll back

Before the tag is pushed, delete a mistaken local tag and correct the commit. After
the tag is public, leave it immutable and publish a patch release. Binary consumers
can follow the rollback procedure in the installation guide; Spec Kitty mission data
does not need a migration or rollback for adapter-only changes.
