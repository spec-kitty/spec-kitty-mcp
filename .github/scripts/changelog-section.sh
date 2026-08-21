#!/bin/sh
# Print the CHANGELOG.md section for one version, used as GitHub release notes.
#
# A release with no changelog entry is treated as an error rather than shipping
# empty notes.
set -eu

[ "$#" -eq 1 ] || {
    echo "usage: $0 <version>" >&2
    exit 2
}
version=$1

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

section=$(awk -v want="$version" '
    /^## / {
        # Section heading, e.g. "## 0.1.0 - 2026-08-06".
        found = ($2 == want)
        if (found) next
    }
    found { print }
' "$repo_root/CHANGELOG.md")

# Trim leading and trailing blank lines.
section=$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

[ -n "$section" ] || {
    echo "changelog-section: no CHANGELOG.md entry found for $version" >&2
    exit 1
}

printf '%s\n' "$section"
