#!/bin/bash
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

# End-to-end test of building COSMOS against a PyPI mirror with public PyPI
# unreachable - the air-gapped PYPI_URL build.
#
# 1. Starts a throwaway PyPI mirror: nginx proxying pypi.org's simple index and
#    rewriting every files.pythonhosted.org link to point back at itself, which
#    is how a Nexus/Artifactory PyPI proxy behaves.
# 2. Temporarily patches the files the build needs changed (see below), backing
#    each one up first and restoring the backup on exit - including any
#    uncommitted changes the file already had.
# 3. Runs `./openc3.sh build` or `./openc3.sh build-ubi` with PYPI_URL and
#    UV_INSECURE_HOST pointed at the mirror, and pypi.org plus
#    files.pythonhosted.org resolved to 127.0.0.1 inside every build container.
# 4. Checks the result and exits non-zero if anything failed.
#
# Files patched for the duration of the run:
#   compose-build.yaml          (build)     extra_hosts on every image build
#   openc3-ruby/Dockerfile-ubi  (build-ubi) only when falling back to the public
#                                           UBI image, which has no /bin/python
#
# No .env edits: PYPI_URL, UV_INSECURE_HOST and the UBI base are exported, and
# openc3.sh gives shell variables precedence over .env.
#
# Usage: scripts/linux/test_pypi_mirror.sh [build|build-ubi] [options] [build flags...]

set -eo pipefail

usage() {
  cat <<EOF
Usage: $0 [build|build-ubi] [options] [build flags...]

Builds COSMOS against a local PyPI mirror with public PyPI blocked, then
verifies the images were built entirely from the mirror.

Modes:
  build        Debian images via ./openc3.sh build (default)
  build-ubi    UBI images via ./openc3.sh build-ubi

Options:
  --cache       Allow the docker layer cache. By default the build runs with
                --no-cache, because a cached layer skips the steps that
                contact the mirror and the log checks below would then fail.
                With --cache those checks only warn.
  --public-ubi  build-ubi only: use registry.access.redhat.com/ubi9/ubi-minimal
                instead of the configured (Iron Bank) base. This happens
                automatically when the configured base cannot be pulled.
  -h, --help    Show this help

Any other argument starting with - is passed through to the build.

Environment:
  MIRROR_PORT   Host port for the mirror (default 8765)
  LOG_FILE      Build log path (default \${TMPDIR:-/tmp}/openc3-pypi-mirror-<mode>.log)
EOF
}

MODE=build
USE_CACHE=0
PUBLIC_UBI=0
EXTRA_FLAGS=()
for arg in "$@"; do
  case "$arg" in
    build|build-ubi) MODE="$arg" ;;
    --cache) USE_CACHE=1 ;;
    --public-ubi) PUBLIC_UBI=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) EXTRA_FLAGS+=("$arg") ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$(dirname -- "$0")/../.."

MIRROR_PORT="${MIRROR_PORT:-8765}"
MIRROR_NAME="openc3-pypi-mirror-test"
MIRROR_IMAGE="nginx:1.29-alpine"
MIRROR_HOST="host.docker.internal:${MIRROR_PORT}"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
LOG_FILE="${LOG_FILE:-${TMP_ROOT}/openc3-pypi-mirror-${MODE}.log}"

# The hosts every build container gets. pypi.org and files.pythonhosted.org go
# nowhere; host.docker.internal already resolves on Docker Desktop but not on a
# Linux engine, so map it to the host gateway explicitly.
BLOCKED_HOSTS=(
  "pypi.org:127.0.0.1"
  "files.pythonhosted.org:127.0.0.1"
  "host.docker.internal:host-gateway"
)

WORK_DIR="$(mktemp -d "${TMP_ROOT}/openc3-pypi-mirror.XXXXXX")"
BACKUP_DIR="${WORK_DIR}/backup"
mkdir -p "${BACKUP_DIR}"
BACKED_UP=()
RESTORE_FAILED=0

# Resolve a setting the way openc3.sh does: shell > .env.local > .env
env_value() {
  local key="$1" value=""
  if [[ -n "${!key+x}" ]]; then
    echo "${!key}"
    return
  fi
  for file in .env .env.local; do
    if [[ -f "$file" ]] && grep -qE "^${key}=" "$file"; then
      value="$(grep -E "^${key}=" "$file" | tail -1 | cut -d= -f2-)"
    fi
  done
  echo "$value"
}

backup_file() {
  local file="$1"
  cp -p "$file" "${BACKUP_DIR}/${file//\//__}"
  BACKED_UP+=("$file")
}

restore_files() {
  local file backup
  for file in "${BACKED_UP[@]}"; do
    backup="${BACKUP_DIR}/${file//\//__}"
    cp -p "$backup" "$file"
    if cmp -s "$backup" "$file"; then
      echo "Restored ${file}"
    else
      echo "ERROR: failed to restore ${file}; the original is at ${backup}" >&2
      RESTORE_FAILED=1
    fi
  done
  BACKED_UP=()
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  echo ""
  echo "=== cleanup"
  restore_files
  docker rm -f "${MIRROR_NAME}" > /dev/null 2>&1 || true
  # Keep the backups if a restore failed; otherwise the work dir is disposable
  if [[ $RESTORE_FAILED -eq 0 ]]; then
    rm -rf "${WORK_DIR}"
  else
    rc=1
  fi
  echo "Build log: ${LOG_FILE}"
  exit $rc
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Backups of patched files: ${BACKUP_DIR} (restored automatically on exit)"

start_mirror() {
  echo "=== starting PyPI mirror on port ${MIRROR_PORT}"
  if docker ps -a --format '{{.Names}}' | grep -qx "${MIRROR_NAME}"; then
    docker rm -f "${MIRROR_NAME}" > /dev/null
  fi
  cat > "${WORK_DIR}/default.conf" <<'EOF'
server {
    listen 8080;
    proxy_ssl_server_name on;
    proxy_http_version 1.1;

    # The simple index, with every download link rewritten from
    # files.pythonhosted.org to this mirror. Compression is disabled upstream
    # so sub_filter can see the body; both the HTML and the JSON (PEP 691)
    # forms that uv requests are rewritten.
    location /simple/ {
        proxy_pass https://pypi.org/simple/;
        proxy_set_header Host pypi.org;
        proxy_set_header Accept-Encoding "";
        sub_filter_types application/vnd.pypi.simple.v1+json application/vnd.pypi.simple.v1+html;
        sub_filter_once off;
        sub_filter "https://files.pythonhosted.org/" "http://$http_host/files/";
    }

    # The distribution files themselves
    location /files/ {
        proxy_pass https://files.pythonhosted.org/;
        proxy_set_header Host files.pythonhosted.org;
    }
}
EOF
  docker run -d --name "${MIRROR_NAME}" -p "${MIRROR_PORT}:8080" \
    -v "${WORK_DIR}/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    "${MIRROR_IMAGE}" > /dev/null
  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null "http://localhost:${MIRROR_PORT}/simple/pip/"; then
      echo "Mirror is up: http://${MIRROR_HOST}"
      return
    fi
    sleep 1
  done
  echo "ERROR: mirror did not answer on http://localhost:${MIRROR_PORT}/simple/pip/" >&2
  docker logs "${MIRROR_NAME}" >&2 || true
  exit 1
}

# Add BLOCKED_HOSTS to the extra_hosts of every service's build section,
# appending to an extra_hosts list the section may already have.
patch_compose_build() {
  echo "=== patching compose-build.yaml"
  backup_file compose-build.yaml
  python3 - compose-build.yaml "${BLOCKED_HOSTS[@]}" <<'EOF'
import sys

path, hosts = sys.argv[1], sys.argv[2:]
lines = open(path).read().split("\n")
entries = [f'        - "{h}"' for h in hosts]
out, i, patched = [], 0, 0
while i < len(lines):
    out.append(lines[i])
    if lines[i] == "    build:":
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > 4):
            j += 1
        block = lines[i + 1 : j]
        if "      extra_hosts:" in block:
            k = block.index("      extra_hosts:") + 1
            block = block[:k] + entries + block[k:]
        else:
            block = ["      extra_hosts:"] + entries + block
        out.extend(block)
        patched += 1
        i = j
        continue
    i += 1
open(path, "w").write("\n".join(out))
print(f"Added extra_hosts to {patched} build sections")
EOF
  local env_args=(--env-file .env)
  [[ -f .env.local ]] && env_args+=(--env-file .env.local)
  if ! docker compose "${env_args[@]}" -f compose.yaml -f compose-build.yaml config -q; then
    echo "ERROR: patched compose-build.yaml is not valid" >&2
    exit 1
  fi
}

# The public UBI image lacks the /bin/python that Dockerfile-ubi removes before
# symlinking python3.12, so a plain rm fails there. Iron Bank does ship it.
patch_dockerfile_ubi() {
  echo "=== patching openc3-ruby/Dockerfile-ubi for the public UBI image"
  backup_file openc3-ruby/Dockerfile-ubi
  sed -i.sedbak \
    -e 's|^\(    \)rm /bin/python && \\$|\1rm -f /bin/python \&\& \\|' \
    -e 's|^\(    \)rm /bin/python3 && \\$|\1rm -f /bin/python3 \&\& \\|' \
    openc3-ruby/Dockerfile-ubi
  rm -f openc3-ruby/Dockerfile-ubi.sedbak
}

select_ubi_base() {
  local registry image tag
  registry="$(env_value OPENC3_UBI_REGISTRY)"
  image="$(env_value OPENC3_UBI_IMAGE)"
  tag="$(env_value OPENC3_UBI_TAG)"
  if [[ $PUBLIC_UBI -eq 0 ]]; then
    echo "=== checking access to ${registry}/${image}:${tag}"
    if docker pull -q "${registry}/${image}:${tag}" > /dev/null 2>&1; then
      return
    fi
    echo "WARNING: cannot pull ${registry}/${image}:${tag}; falling back to the public UBI image"
  fi
  export OPENC3_UBI_REGISTRY=registry.access.redhat.com
  export OPENC3_UBI_IMAGE=ubi9/ubi-minimal
  export OPENC3_UBI_TAG="${tag:-9.6}"
  echo "Using ${OPENC3_UBI_REGISTRY}/${OPENC3_UBI_IMAGE}:${OPENC3_UBI_TAG}"
  patch_dockerfile_ubi
}

run_build() {
  local cache_flags=()
  [[ $USE_CACHE -eq 0 ]] && cache_flags=(--no-cache)
  export PYPI_URL="http://${MIRROR_HOST}"
  export UV_INSECURE_HOST="${MIRROR_HOST}"
  export BUILDKIT_PROGRESS=plain
  echo "=== ./openc3.sh ${MODE} with PYPI_URL=${PYPI_URL}"
  echo "Logging to ${LOG_FILE}"
  local status=0
  if [[ "$MODE" == "build" ]]; then
    ./openc3.sh build "${cache_flags[@]}" "${EXTRA_FLAGS[@]}" 2>&1 | tee "${LOG_FILE}" || status=$?
  else
    local host_flags=() h
    for h in "${BLOCKED_HOSTS[@]}"; do host_flags+=("--add-host=${h}"); done
    ./openc3.sh build-ubi "${cache_flags[@]}" "${host_flags[@]}" "${EXTRA_FLAGS[@]}" 2>&1 | tee "${LOG_FILE}" || status=$?
  fi
  return $status
}

RESULTS=()
FAILURES=0
pass() { RESULTS+=("PASS  $1"); }
fail() { RESULTS+=("FAIL  $1"); FAILURES=$((FAILURES + 1)); }
warn() { RESULTS+=("WARN  $1"); }

# A log check fails outright on a no-cache build and only warns with --cache,
# where a cached layer legitimately skips the step that prints the line.
check_log() {
  local description="$1" pattern="$2"
  if grep -qF -- "$pattern" "${LOG_FILE}"; then
    pass "$description"
  elif [[ $USE_CACHE -eq 1 ]]; then
    warn "$description (not in log; the step may have been cached)"
  else
    fail "$description"
  fi
}

# Count pythonhosted.org and mirror URLs in a lock; pass only if the lock
# points entirely at the mirror.
check_lock() {
  local description="$1" lock="$2" public mirror
  if [[ ! -s "$lock" ]]; then
    fail "$description (lock not found)"
    return
  fi
  public="$(grep -c 'files.pythonhosted.org' "$lock" || true)"
  mirror="$(grep -c "${MIRROR_HOST}" "$lock" || true)"
  if [[ "$public" -eq 0 && "$mirror" -gt 0 ]]; then
    pass "$description (${mirror} mirror URLs, 0 pythonhosted.org)"
  else
    fail "$description (${mirror} mirror URLs, ${public} pythonhosted.org)"
  fi
}

verify() {
  local suffix="" registry namespace tag base_image init_image cid gem
  [[ "$MODE" == "build-ubi" ]] && suffix="-ubi"
  registry="$(env_value OPENC3_REGISTRY)"
  namespace="$(env_value OPENC3_NAMESPACE)"
  tag="$(env_value OPENC3_TAG)"
  base_image="${registry}/${namespace}/openc3-base${suffix}:${tag}"
  init_image="${registry}/${namespace}/openc3-cosmos-init${suffix}:${tag}"

  echo ""
  echo "=== verifying"
  check_log "pip installed uv from the mirror" "Looking in indexes: ${PYPI_URL}/simple"
  check_log "openc3/python relocked against the mirror" "relock /openc3/python/uv.lock against ${PYPI_URL}"
  check_log "demo plugin relocked against the mirror" "relock /openc3/plugins/packages/openc3-cosmos-demo/uv.lock against ${PYPI_URL}"
  check_log "verify-uv-cache.sh passed offline" "offline UV cache verified"

  docker run --rm --entrypoint cat "${base_image}" /openc3/python/uv.lock > "${WORK_DIR}/base-uv.lock" 2>/dev/null || true
  check_lock "openc3-base${suffix} uv.lock points at the mirror" "${WORK_DIR}/base-uv.lock"

  mkdir -p "${WORK_DIR}/gems"
  if cid="$(docker create "${init_image}" 2>/dev/null)"; then
    docker cp "${cid}:/openc3/plugins/gems/." "${WORK_DIR}/gems" > /dev/null 2>&1 || true
    docker rm "${cid}" > /dev/null
  fi
  gem="$(find "${WORK_DIR}/gems" -name 'openc3-cosmos-demo-*.gem' | head -1)"
  if [[ -n "$gem" ]]; then
    tar -xOf "$gem" data.tar.gz | tar -xzOf - uv.lock > "${WORK_DIR}/demo-uv.lock" 2>/dev/null || true
  fi
  check_lock "demo plugin gem uv.lock points at the mirror" "${WORK_DIR}/demo-uv.lock"

  local downloads
  downloads="$(docker logs "${MIRROR_NAME}" 2>&1 | grep -c 'GET /files/' || true)"
  if [[ "$downloads" -gt 0 ]]; then
    pass "mirror served ${downloads} distribution downloads"
  elif [[ $USE_CACHE -eq 1 ]]; then
    warn "mirror served no downloads (every download step may have been cached)"
  else
    fail "mirror served no downloads"
  fi
}

report() {
  local line verdict="PASSED"
  [[ $FAILURES -gt 0 ]] && verdict="FAILED"
  echo ""
  echo "=== PyPI mirror ${MODE}: ${verdict}"
  for line in "${RESULTS[@]}"; do echo "  ${line}"; done
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### PyPI mirror ${MODE}: ${verdict}"
      for line in "${RESULTS[@]}"; do echo "- \`${line%% *}\` ${line#*  }"; done
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

start_mirror
if [[ "$MODE" == "build" ]]; then
  patch_compose_build
else
  select_ubi_base
fi

BUILD_STATUS=0
run_build || BUILD_STATUS=$?
if [[ $BUILD_STATUS -eq 0 ]]; then
  pass "./openc3.sh ${MODE} succeeded"
  verify
else
  fail "./openc3.sh ${MODE} exited ${BUILD_STATUS} (see ${LOG_FILE})"
fi
report
[[ $FAILURES -eq 0 ]]
