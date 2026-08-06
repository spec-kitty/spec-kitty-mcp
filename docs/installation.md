# Installation and upgrades

`spec-kitty-mcp` is a standalone executable. Installing, upgrading, or removing
it does not modify Spec Kitty or any Spec Kitty project.

## Prerequisites

- An installed `spec-kitty` executable whose `orchestrator-api` contract is
  compatible with the adapter
- Git
- An initialized Spec Kitty project to bind with `--project-root`
- `sha256sum` or `shasum` for release verification

The server negotiates compatibility at startup and exits before serving MCP
requests if the installed Spec Kitty contract is incompatible.

## Install a release binary

Set the release version and target to match the asset you are installing:

| Platform | Architecture | Target |
|---|---|---|
| Linux | x86_64 | `x86_64-linux-musl` |
| Linux | ARM64 | `aarch64-linux-musl` |
| macOS | Intel | `x86_64-macos` |
| macOS | Apple Silicon | `aarch64-macos` |

```bash
VERSION=0.1.0
TARGET=x86_64-linux-musl
ASSET="spec-kitty-mcp-${VERSION}-${TARGET}"
RELEASE_URL="https://github.com/LynnColeArt/spec-kitty-mcp/releases/download/v${VERSION}"

curl -fLO "${RELEASE_URL}/${ASSET}"
curl -fLO "${RELEASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
install -Dm755 "${ASSET}" "$HOME/.local/bin/spec-kitty-mcp"
spec-kitty-mcp --version
```

On systems with `shasum` instead of `sha256sum`, verify with:

```bash
shasum -a 256 -c "${ASSET}.sha256"
```

Do not install a binary whose checksum does not match its release sidecar.
The initial macOS binaries are not code-signed or notarized.

## Build and install from source

Use the Zig version declared by `build.zig.zon`, then build and copy the local
binary:

```bash
git clone https://github.com/LynnColeArt/spec-kitty-mcp.git
cd spec-kitty-mcp
zig build check
zig build -Doptimize=ReleaseSafe -Dstrip=true -Dversion=0.1.0
install -Dm755 zig-out/bin/spec-kitty-mcp "$HOME/.local/bin/spec-kitty-mcp"
```

Run the installed executable against a project before registering it with an
MCP host:

```bash
spec-kitty-mcp --version
spec-kitty-mcp --project-root /path/to/initialized-project </dev/null
```

The second command should report the bound project and negotiated Spec Kitty
contract on stderr, then exit cleanly at stdin EOF.

## Configure an MCP host

Pass an absolute executable path and one initialized project root per server
process:

```text
$HOME/.local/bin/spec-kitty-mcp \
  --project-root /path/to/initialized-project
```

If `spec-kitty` is not on the MCP host's `PATH`, also pass:

```text
--spec-kitty-bin /absolute/path/to/spec-kitty
```

See [Codex setup](codex-setup.md) for complete host configuration examples.

## Upgrade safely

Download and verify the new release before replacing the running binary. Keep
the current executable as a rollback copy until the new version negotiates
successfully:

```bash
INSTALL_DIR="$HOME/.local/bin"
cp "${INSTALL_DIR}/spec-kitty-mcp" "${INSTALL_DIR}/spec-kitty-mcp.previous"
install -Dm755 "${ASSET}" "${INSTALL_DIR}/spec-kitty-mcp.new"
mv "${INSTALL_DIR}/spec-kitty-mcp.new" "${INSTALL_DIR}/spec-kitty-mcp"
"${INSTALL_DIR}/spec-kitty-mcp" --version
```

Restart the MCP host so it launches the replacement executable, then call
`tools/list` or start a fresh host session to confirm startup negotiation and
tool discovery. Existing Spec Kitty mission state does not require migration by
this adapter.

If startup or negotiation fails, restore the prior executable and restart the
host:

```bash
mv "$HOME/.local/bin/spec-kitty-mcp.previous" \
  "$HOME/.local/bin/spec-kitty-mcp"
```

## Remove

Remove the MCP host entry first so it no longer tries to launch the server,
then remove the executable and any rollback copy:

```bash
rm "$HOME/.local/bin/spec-kitty-mcp"
rm -f "$HOME/.local/bin/spec-kitty-mcp.previous"
```

No Spec Kitty project files, mission artifacts, worktrees, or configuration are
removed by uninstalling the adapter.

## Troubleshooting

- `ContractRejected` means the installed Spec Kitty orchestrator contract and
  adapter provider version do not overlap. Upgrade the older component or roll
  back the newer one.
- `ExecutableNotFound` means the MCP process cannot resolve `spec-kitty`; pass
  an absolute `--spec-kitty-bin` path.
- A missing `.kittify/config.yaml` or `.git` entry means `--project-root` does
  not identify an initialized Spec Kitty project.
- JSON on stdout other than MCP messages indicates a wrapper or launcher is
  writing to the protocol stream. Send launcher diagnostics to stderr.
