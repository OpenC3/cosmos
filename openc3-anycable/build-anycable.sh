#!/usr/bin/env bash
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Build the anycable-go binaries bundled in openc3-anycable/ from an anycable
# checkout. Mirrors anycable's .github/workflows/release-binaries.yml
# (plain, non-mruby builds) and copies the results next to this script.
#
# Usage:
#   openc3-anycable/build-anycable.sh [ANYCABLE_DIR]
#
# ANYCABLE_DIR defaults to $ANYCABLE_DIR, then ../anycable relative to the
# cosmos repo root. It must be a git clone of github.com/anycable/anycable
# (or a fork) so the version can be read from its tags.
#
# Env overrides:
#   VERSION  - version string to stamp (default: latest v* tag, without "v", plus ".1")
#   SHA      - commit sha to stamp (default: short HEAD of ANYCABLE_DIR)
#   OUTDIR   - where to copy the binaries (default: this script's directory)
#   ANYCABLE_TELEMETRY_TOKEN - stamped into telemetry.auth (default: empty)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANYCABLE_DIR="${1:-${ANYCABLE_DIR:-$REPO_ROOT/../anycable}}"
OUTDIR="${OUTDIR:-$SCRIPT_DIR}"

if [[ ! -f "$ANYCABLE_DIR/cmd/anycable-go/main.go" ]]; then
  echo "error: $ANYCABLE_DIR is not an anycable checkout" >&2
  echo "clone it with: gh repo fork anycable/anycable --clone (or git clone https://github.com/anycable/anycable.git)" >&2
  exit 1
fi
ANYCABLE_DIR="$(cd "$ANYCABLE_DIR" && pwd)"
OUTDIR="$(mkdir -p "$OUTDIR" && cd "$OUTDIR" && pwd)"

cd "$ANYCABLE_DIR"

PKG=github.com/anycable/anycable-go
# Default: latest v* tag with a ".1" build suffix, e.g. v1.6.18 -> 1.6.18.1
VERSION="${VERSION:-$(git tag -l --sort=-version:refname "v*" | head -n1 | sed 's/^v//').1}"
SHA="${SHA:-$(git rev-parse HEAD | cut -c -7)}"
TOKEN="${ANYCABLE_TELEMETRY_TOKEN:-}"

LD_FLAGS="-s -w -X ${PKG}/telemetry.auth=${TOKEN} -X ${PKG}/version.version=${VERSION} -X ${PKG}/version.sha=${SHA}"

echo "anycable=${ANYCABLE_DIR} version=${VERSION} sha=${SHA} outdir=${OUTDIR}"
[[ -z "$TOKEN" ]] && echo "note: ANYCABLE_TELEMETRY_TOKEN unset, telemetry.auth will be empty"

for goarch in amd64 arm64; do
  name="anycable-go-linux-${goarch}"
  echo "==> building ${OUTDIR}/${name}"
  env CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" \
    go build -ldflags "$LD_FLAGS" -a -o "${OUTDIR}/${name}" cmd/anycable-go/main.go
done

go version "${OUTDIR}/anycable-go-linux-amd64" "${OUTDIR}/anycable-go-linux-arm64"
ls -lh "${OUTDIR}"/anycable-go-linux-*
