#!/bin/sh
set -eu

usage() {
    echo "usage: $0 <version> <zig-target>" >&2
    echo "example: $0 0.1.0 x86_64-linux-musl" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
release_version=$1
release_target=$2

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

manifest_version=$(sed -n 's/^[[:space:]]*\.version = "\([^"]*\)",/\1/p' build.zig.zon)
[ -n "$manifest_version" ] || {
    echo "release check: could not read build.zig.zon version" >&2
    exit 1
}
[ "$release_version" = "$manifest_version" ] || {
    echo "release check: requested $release_version but build.zig.zon declares $manifest_version" >&2
    exit 1
}

if [ "${RELEASE_ALLOW_DIRTY:-0}" != 1 ] && [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    echo "release check: tracked or untracked changes are present" >&2
    exit 1
fi

zig build check
zig build smoke-read-only
zig build smoke-mutations
zig build -Doptimize=ReleaseSafe -Dstrip=true -Dversion="$release_version"

reported_version=$(./zig-out/bin/spec-kitty-mcp --version)
[ "$reported_version" = "spec-kitty-mcp $release_version" ] || {
    echo "release check: binary reported unexpected version: $reported_version" >&2
    exit 1
}

./scripts/package-release.sh "$release_version" "$release_target"

echo "release check: $release_version for $release_target is ready to tag"
