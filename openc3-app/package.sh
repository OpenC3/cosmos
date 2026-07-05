#!/usr/bin/env bash
#
# Build a NATIVE installer for the current host OS and architecture.
#
# Native installers must be produced on their own platform (a .dmg needs macOS,
# an .msi/.exe needs Windows, .deb/.rpm/AppImage need Linux), so this script
# packages for whatever machine it runs on:
#
#   macOS   -> .app + .dmg            (dist/installers/)
#   Linux   -> .deb, .rpm, AppImage   (run inside a Linux container for Linux)
#   Windows -> use package.ps1
#
# The output architecture matches the host (e.g. arm64 on Apple Silicon).

set -euo pipefail

cd "$(dirname "$0")"

OS="$(uname -s)"
ARCH="$(uname -m)"
echo "Packaging OpenC3 COSMOS for ${OS} ${ARCH}"

# 1. Build the optimized release binary (GUI enabled).
echo "Building release binary..."
cargo build --release

# 2. Ensure the packaging tool is available.
if ! cargo packager --version >/dev/null 2>&1; then
  echo "Installing cargo-packager..."
  cargo install cargo-packager --locked
fi

# 3. Produce the host-native installer(s).
OUT="dist/installers"
mkdir -p "$OUT"
echo "Building installer(s) into ${OUT}/ ..."
cargo packager --release --out-dir "$OUT"

echo
echo "Done. Installers:"
find "$OUT" -maxdepth 1 -type f \
  \( -name '*.dmg' -o -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \
     -o -name '*.msi' -o -name '*.exe' \) -print 2>/dev/null || true
