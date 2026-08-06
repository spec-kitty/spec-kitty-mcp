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

case "$release_version" in
    ""|*[!0-9A-Za-z.+-]*) usage ;;
esac
case "$release_target" in
    ""|*[!0-9A-Za-z._-]*) usage ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/spec-kitty-mcp-package.XXXXXX")

cleanup() {
    rm -rf -- "$stage_dir"
}
trap cleanup EXIT HUP INT TERM

zig build \
    --build-file "$repo_root/build.zig" \
    --prefix "$stage_dir" \
    -Doptimize=ReleaseSafe \
    -Dstrip=true \
    -Dtarget="$release_target" \
    -Dversion="$release_version"

binary_name=spec-kitty-mcp
case "$release_target" in
    *windows*) binary_name=$binary_name.exe ;;
esac

source_binary=$stage_dir/bin/$binary_name
[ -f "$source_binary" ] || {
    echo "package error: built binary not found at $source_binary" >&2
    exit 1
}

dist_dir=$repo_root/dist
mkdir -p "$dist_dir"
artifact_name=spec-kitty-mcp-$release_version-$release_target
case "$release_target" in
    *windows*) artifact_name=$artifact_name.exe ;;
esac
artifact_path=$dist_dir/$artifact_name
cp "$source_binary" "$artifact_path"
chmod 0755 "$artifact_path"

checksum_path=$artifact_path.sha256
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dist_dir" && sha256sum "$artifact_name" > "$artifact_name.sha256")
    (cd "$dist_dir" && sha256sum -c "$artifact_name.sha256")
elif command -v shasum >/dev/null 2>&1; then
    checksum=$(shasum -a 256 "$artifact_path" | awk '{print $1}')
    printf '%s  %s\n' "$checksum" "$artifact_name" > "$checksum_path"
    (cd "$dist_dir" && shasum -a 256 -c "$artifact_name.sha256")
else
    echo "package error: sha256sum or shasum is required" >&2
    exit 1
fi

printf 'artifact: %s\nchecksum: %s\n' "$artifact_path" "$checksum_path"
