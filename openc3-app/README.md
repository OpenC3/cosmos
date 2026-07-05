# OpenC3 COSMOS Native App

A single cross-platform Rust application that installs and manages a complete
OpenC3 COSMOS environment. It launches a graphical control panel by default and
exposes the full `openc3.sh` command set on the command line for headless use.

## What it does

The app provides these functions (see `requirements.md`):

1. **Install Docker** — installs a working Docker / docker compose engine for
   the native platform if one is not already available.
2. **Install Python** — installs an isolated Python runtime under the
   `python/` subfolder (via [`uv`](https://github.com/astral-sh/uv)).
3. **Install COSMOS** — downloads the OpenC3 COSMOS environment into the
   `cosmos/` subfolder.
4. **Launch & monitor** — brings the COSMOS containers up with docker compose
   and continuously monitors their health.
5. **GUI** — an [Iced](https://iced.rs)-based control panel, on by default, with
   a fully headless mode.
6. **CLI** — command-line functionality equivalent to `openc3.sh`.

Planned (not yet implemented): supervising host-side Python microservices, and
an [Iroh](https://iroh.computer) client/server transport to talk to them. See
`src/future.rs`.

## Layout

Everything an install needs lives in subfolders of a single application root
(overridable with `--root` or `OPENC3_APP_HOME`):

```
<root>/
  bin/              downloaded helper tools (uv, ...)
  python/           isolated Python runtime + venv
  cosmos/           COSMOS environment (compose.yaml, .env, support dirs)
```

The default root depends on how the app is run:

- **Portable binary** (a writable folder, e.g. unzipped next to the executable):
  the directory containing the executable — components sit beside the binary.
- **Installed app** (inside a macOS `.app` bundle, or any read-only/system
  location like `/Applications`, `Program Files`, `/usr`): a per-user data
  directory, so installs never write into a code-signed/read-only bundle:
  - macOS: `~/Library/Application Support/OpenC3`
  - Windows: `%APPDATA%\OpenC3`
  - Linux: `$XDG_DATA_HOME/openc3` (or `~/.local/share/openc3`)
- **`cargo run`** (dev): the current working directory.

## Usage

```bash
# First-time setup: install Docker, Python, and COSMOS
openc3 install all

# Or individually
openc3 install docker
openc3 install python
openc3 install cosmos --tag latest

# Lifecycle (equivalent to openc3.sh)
openc3 start          # build (dev) + run
openc3 run            # start containers (http://localhost:2900)
openc3 stop           # graceful stop + down
openc3 restart
openc3 status         # container health summary
openc3 logs -f
openc3 monitor        # continuous headless health monitor
openc3 cleanup --force

# COSMOS CLI inside a container
openc3 cli generate plugin MyPlugin
openc3 cliroot validate myplugin.gem

# Utilities (encode, hash, save, load, tag, push, pull, clean)
openc3 util hash "my password"
openc3 util pull 7.0.0

# Upgrade a git-based install
openc3 upgrade v6.4.1 --preview

# Graphical control panel (also the default with no subcommand)
openc3 gui
```

Run any command with `--headless` to suppress the GUI, or `--enterprise` to
treat the install as COSMOS Enterprise.

## Building

All building happens inside Docker, so the only host requirement is Docker.

```bash
# Build release executables for every supported platform into ./dist/
./build.sh

# Build specific targets
./build.sh x86_64-unknown-linux-gnu aarch64-apple-darwin
```

Supported targets:

| Platform | Targets | Toolchain |
| --- | --- | --- |
| Linux | `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` | cargo-zigbuild |
| Windows | `x86_64-pc-windows-gnu` | cargo-zigbuild |
| macOS | `x86_64-apple-darwin`, `aarch64-apple-darwin` | cargo-zigbuild + macOS SDK |

(Windows uses the GNU ABI so cargo-zigbuild can compile the C/assembly in
transitive dependencies such as `ring`, which the Iroh bridge pulls in.)

macOS targets require a macOS SDK (which cannot be redistributed in the image).
Provide one with `MACOS_SDK`:

```bash
MACOS_SDK=/path/to/MacOSX.sdk ./build.sh x86_64-apple-darwin aarch64-apple-darwin
```

### Native installers

Native installers are built for the **host OS and architecture** (a `.dmg` needs
macOS, an `.msi`/`.exe` needs Windows, `.deb`/`.rpm`/AppImage need Linux), using
[`cargo-packager`](https://github.com/crabnebula-dev/cargo-packager). Output
lands in `dist/installers/`.

```bash
# macOS / Linux
./package.sh
```

```powershell
# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File .\package.ps1
```

| Host | Produces |
| --- | --- |
| macOS | `OpenC3 COSMOS.app` + `OpenC3 COSMOS_<ver>_<arch>.dmg` |
| Linux | `.deb`, `.rpm`, `.AppImage` |
| Windows | `.msi` (WiX) and/or `.exe` (NSIS) |

The architecture matches the build host (e.g. `aarch64` on Apple Silicon). To
produce Linux installers from a non-Linux host, run `./package.sh` inside a
Linux container. Installer metadata (product name, identifier, etc.) lives under
`[package.metadata.packager]` in `Cargo.toml`.

### Local development build

For quick iteration on the host (requires a Rust toolchain):

```bash
cargo run                       # launch the GUI
cargo run -- status             # run a CLI command
cargo build --no-default-features   # smaller headless-only binary
```

## License

AGPL-3.0-only (matching OpenC3 COSMOS Core).
