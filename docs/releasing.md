# Release procedure

Publishing a release is an intentional human gate. Packaging and verification
are automated locally; creating and pushing the version tag is not.

## Prepare

1. Update `.version` in `build.zig.zon` to the intended release version.
2. Update compatibility notes and installation examples when their values
   change.
3. Commit and push those changes directly to `main`.
4. Confirm the local branch is clean and synchronized with `origin/main`.

The release check refuses a version that differs from `build.zig.zon` and
refuses a dirty repository by default.

## Verify and package

Run the full unit, installed-CLI, mutation, packaging, version, and checksum
checks for each target to be published:

```bash
./scripts/release-check.sh 0.1.0 x86_64-linux-musl
```

The command requires an installed compatible `spec-kitty` executable because
the two MCP smoke suites exercise the live orchestrator contract. It writes the
versioned standalone binary and its verified `.sha256` sidecar to `dist/`.

For another architecture, rerun the command with its Zig target. Do not rename
an artifact after checksum generation; regenerate the pair instead.

## Tag

Inspect the exact commit and packaged assets before creating the tag:

```bash
git status --short --branch
git log -1 --oneline
ls -lh dist/
```

After explicit release approval, create an annotated tag and push only that
tag:

```bash
git tag -a v0.1.0 -m "spec-kitty-mcp 0.1.0"
git push origin v0.1.0
```

Do not move or reuse a published version tag. Correct a release with a new
patch version.

## Publish assets

Create the GitHub release from the pushed tag and attach every binary together
with its matching `.sha256` file. Copy release notes from the changes since the
previous tag and call out:

- supported Zig build target names
- the negotiated Spec Kitty orchestrator contract
- MCP tool additions or removals
- safety or compatibility changes
- known limitations

Verify that the public asset URLs and the commands in
[Installation and upgrades](installation.md) work from a fresh temporary
directory before announcing the release.

## Abort or roll back

Before the tag is pushed, delete a mistaken local tag and correct the commit.
After the tag is public, leave it immutable and publish a patch release. Binary
consumers can follow the rollback procedure in the installation guide; Spec
Kitty mission data does not need a migration or rollback for adapter-only
changes.
