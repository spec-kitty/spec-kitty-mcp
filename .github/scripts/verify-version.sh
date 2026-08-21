#!/bin/sh
# Confirm a requested release version matches the version declared in
# build.zig.zon. Mirrors the same gate in scripts/release-check.sh so a tag can
# never publish artifacts that disagree with the manifest.
set -eu

[ "$#" -eq 1 ] || {
    echo "usage: $0 <version>" >&2
    exit 2
}
requested_version=$1

case "$requested_version" in
    ""|*[!0-9A-Za-z.+-]*)
        echo "verify-version: refusing malformed version '$requested_version'" >&2
        exit 2
        ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

manifest_version=$(sed -n 's/^[[:space:]]*\.version = "\([^"]*\)",/\1/p' "$repo_root/build.zig.zon")
[ -n "$manifest_version" ] || {
    echo "verify-version: could not read build.zig.zon version" >&2
    exit 1
}

[ "$requested_version" = "$manifest_version" ] || {
    echo "verify-version: requested $requested_version but build.zig.zon declares $manifest_version" >&2
    exit 1
}

echo "verify-version: $requested_version matches build.zig.zon"
