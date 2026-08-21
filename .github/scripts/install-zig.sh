#!/bin/sh
# Install a pinned Zig toolchain and expose it on PATH for later workflow steps.
#
# The version and checksum are pinned deliberately: a release artifact should be
# reproducible from the workflow file alone, without trusting a third-party
# action or a floating "latest" download.
set -eu

zig_version=0.16.0
zig_host=x86_64-linux
zig_sha256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00

install_root=${ZIG_INSTALL_ROOT:-$HOME/.local/share/zig}
tarball=zig-$zig_host-$zig_version.tar.xz
url=https://ziglang.org/download/$zig_version/$tarball

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/install-zig.XXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT HUP INT TERM

echo "install-zig: downloading $url"
curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
    --output "$work_dir/$tarball" "$url"

printf '%s  %s\n' "$zig_sha256" "$work_dir/$tarball" > "$work_dir/zig.sha256"
sha256sum -c "$work_dir/zig.sha256"

rm -rf -- "$install_root"
mkdir -p -- "$install_root"
tar -xJf "$work_dir/$tarball" -C "$install_root" --strip-components=1

zig_bin=$install_root/zig
[ -x "$zig_bin" ] || {
    echo "install-zig: no executable zig at $zig_bin" >&2
    exit 1
}

installed_version=$("$zig_bin" version)
[ "$installed_version" = "$zig_version" ] || {
    echo "install-zig: expected $zig_version but binary reports $installed_version" >&2
    exit 1
}

if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$install_root" >> "$GITHUB_PATH"
fi

echo "install-zig: installed Zig $installed_version at $install_root"
