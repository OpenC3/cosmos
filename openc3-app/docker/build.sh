#!/usr/bin/env bash
#
# In-container cross-build driver. Builds release executables for the requested
# targets and copies them into /work/dist/<target>/. Run via the Docker build
# environment image (see docker/Dockerfile.build and ../build.sh).
#
# Usage:
#   openc3-build [TARGET ...]
#
# With no arguments, every supported target is attempted. macOS targets are
# only built when a macOS SDK is available (mount it and set SDKROOT).

set -euo pipefail

# Windows uses the GNU ABI (not MSVC) so cargo-zigbuild can compile the C/asm
# in transitive deps like `ring` (pulled in by iroh); the MSVC cross-toolchain
# can't build ring cleanly.
ALL_TARGETS=(
  x86_64-unknown-linux-gnu
  aarch64-unknown-linux-gnu
  x86_64-pc-windows-gnu
  x86_64-apple-darwin
  aarch64-apple-darwin
)

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=("${ALL_TARGETS[@]}")
fi

DIST=/work/dist
mkdir -p "$DIST"

# Track outcomes for an accurate end-of-run summary (don't just list whatever
# happens to be in dist/ — that includes stale files from earlier runs).
STAGED=()
SKIPPED=()
FAILED=()

build_one() {
  local target="$1"
  echo "=============================================================="
  echo "Building $target"
  echo "=============================================================="

  local rc=0
  case "$target" in
    *-pc-windows-gnu)
      cargo zigbuild --release --target "$target" || rc=$?
      ;;
    *-apple-darwin)
      if [[ -z "${SDKROOT:-}" ]]; then
        echo "SKIP $target: no macOS SDK. Mount an SDK and set SDKROOT to build."
        SKIPPED+=("$target")
        return 0
      fi
      cargo zigbuild --release --target "$target" || rc=$?
      ;;
    *-unknown-linux-gnu)
      # Pin a portable glibc so the binaries run on older distros too.
      cargo zigbuild --release --target "${target}.2.17" || rc=$?
      ;;
    *)
      echo "Unknown target: $target" >&2
      return 1
      ;;
  esac

  if [[ $rc -ne 0 ]]; then
    echo "BUILD FAILED for $target (exit $rc)" >&2
    return 1
  fi

  # Locate and stage the produced binary.
  local bin="openc3"
  [[ "$target" == *windows* ]] && bin="openc3.exe"
  local src="/work/target/${target}/release/${bin}"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: expected binary not found: $src" >&2
    return 1
  fi
  local out="${DIST}/${target}"
  local dest="${out}/${bin}"
  mkdir -p "$out"

  # Always remove the previous artifact first so the new one gets a FRESH inode.
  # macOS caches code-signature verdicts per inode; if an earlier (badly signed)
  # build was executed at this path, overwriting it in place keeps the cached
  # rejection and the binary is SIGKILLed even when correctly signed.
  rm -f "$dest"

  if [[ "$target" == *-apple-darwin ]]; then
    # macOS arm64 binaries linked by LLD/zig carry a "linker-signed" ad-hoc
    # signature that AMFI rejects at exec time, so they MUST be re-signed with a
    # plain ad-hoc signature. x86_64 binaries are emitted without a signature
    # (and none is required to run), and LLD leaves no header room for one, so
    # rcodesign can fail there with "insufficient room"; that's tolerable.
    echo "Re-signing $target binary (ad-hoc) with rcodesign..."
    if rcodesign sign "$src" "$dest"; then
      :
    else
      if [[ "$target" == aarch64-* ]]; then
        echo "ERROR: arm64 macOS binary requires a valid signature but signing failed." >&2
        return 1
      fi
      echo "WARNING: ad-hoc signing failed for $target; staging the unsigned binary" >&2
      echo "         (x86_64 macOS binaries run unsigned; sign on a Mac for distribution)." >&2
      cp "$src" "$dest"
    fi
  else
    cp "$src" "$dest"
  fi

  STAGED+=("$dest")
  echo "Staged ${dest}"
}

for target in "${TARGETS[@]}"; do
  if ! build_one "$target"; then
    FAILED+=("$target")
  fi
done

echo
echo "=============================================================="
echo "Build summary"
echo "=============================================================="
if [[ ${#STAGED[@]} -gt 0 ]]; then
  echo "Built this run:"
  for a in "${STAGED[@]}"; do echo "  $a"; done
else
  echo "Built this run: (none)"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "Skipped (not rebuilt): ${SKIPPED[*]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Failed: ${FAILED[*]}" >&2
  exit 1
fi
