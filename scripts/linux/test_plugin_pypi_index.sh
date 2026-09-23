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

# End-to-end test of runtime plugin Python installs against the configured
# pypi_url - the index handling in openc3/bin/uvinstall and PypiUrl.build_args.
#
# Every case runs openc3/bin/uvinstall inside the openc3-operator image, with
# this checkout's openc3/bin and openc3/lib mounted over the image's copies, so
# the working tree is what gets tested and no rebuild is needed. The index
# arguments come from OpenC3::PypiUrl.build_args, exactly as PluginModel builds
# them, and each case gets an empty UV cache so nothing installs from the seed.
#
# A throwaway nginx on a private docker network serves three indexes:
#   http://<mirror>:8080/pypi/     pypi.org proxy, download links rewritten to
#                                  itself (a Nexus/Artifactory PyPI proxy)
#   http://<mirror>:8080/private/  an operator index that serves nothing
#   https://<mirror>:8443/pypi/    the pypi.org proxy behind a self-signed cert
#
# Cases:
#   1. A plugin generated with `cli generate plugin --python`, locked with
#      `uv lock` and built into a gem, installs via `uv sync --frozen`.
#   2. The demo plugin's python deps install without a setuptools shim, both
#      from its committed uv.lock and from pyproject.toml alone.
#   3. With pypi_url set to the private index, an unlocked plugin whose
#      [tool.uv].index or [tool.uv].sources name its author's index fails, and
#      the mirror's access log shows only the private index was queried. The
#      same plugin installs from the author's index at the default pypi_url.
#   4. The self-signed index fails certificate verification without
#      UV_ALLOW_INSECURE_HOST, and installs with it or with the deprecated
#      PIP_ENABLE_TRUSTED_HOST.
#
# Cases 3 and 4 resolve pypi.org and files.pythonhosted.org to 127.0.0.1 in the
# install container, so the local indexes are the only ones reachable. Cases 1
# and 2 need internet access: a frozen sync downloads from the URLs in uv.lock.
#
# Usage: scripts/linux/test_plugin_pypi_index.sh [options]

set -eo pipefail

usage() {
  cat <<EOF
Usage: $0 [options]

Runs openc3/bin/uvinstall from this checkout against local PyPI indexes and
verifies how plugin Python dependencies resolve against pypi_url.

Options:
  --image IMAGE  Image to run the installs in (default
                 \${OPENC3_REGISTRY}/\${OPENC3_NAMESPACE}/openc3-operator:\${OPENC3_TAG}
                 from the shell or .env). Build it first with ./openc3.sh build.
  -h, --help     Show this help

Environment:
  LOG_DIR   Directory for per-case install logs (default
            \${TMPDIR:-/tmp}/openc3-plugin-pypi-index)
EOF
}

IMAGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$(dirname -- "$0")/../.."
REPO_ROOT="$(pwd)"

MIRROR_NAME="openc3-pypi-index-test"
MIRROR_IMAGE="nginx:1.29-alpine"
NETWORK_NAME="openc3-pypi-index-test"
DEFAULT_INDEX="https://pypi.org/simple"
AUTHOR_INDEX="http://${MIRROR_NAME}:8080/pypi/simple"
PRIVATE_INDEX="http://${MIRROR_NAME}:8080/private/simple"
TLS_INDEX="https://${MIRROR_NAME}:8443/pypi/simple"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
LOG_DIR="${LOG_DIR:-${TMP_ROOT}/openc3-plugin-pypi-index}"

BLOCKED_HOSTS=(
  "--add-host=pypi.org:127.0.0.1"
  "--add-host=files.pythonhosted.org:127.0.0.1"
)

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

if [[ -z "$IMAGE" ]]; then
  IMAGE="$(env_value OPENC3_REGISTRY)/$(env_value OPENC3_NAMESPACE)/openc3-operator:$(env_value OPENC3_TAG)"
fi

WORK_DIR="$(mktemp -d "${TMP_ROOT}/openc3-plugin-pypi-index.XXXXXX")"
FIXTURES="${WORK_DIR}/fixtures"
mkdir -p "${FIXTURES}" "${LOG_DIR}"
rm -f "${LOG_DIR}"/*.log

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  echo ""
  echo "=== cleanup"
  docker rm -f "${MIRROR_NAME}" > /dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" > /dev/null 2>&1 || true
  # The image user may own files it wrote into the fixtures on a Linux engine
  docker run --rm -v "${WORK_DIR}:/work" --entrypoint rm "${MIRROR_IMAGE}" -rf /work/fixtures > /dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
  echo "Install logs: ${LOG_DIR}"
  exit $rc
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_mirror() {
  echo "=== starting PyPI indexes"
  docker rm -f "${MIRROR_NAME}" > /dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" > /dev/null 2>&1 || true
  docker network create "${NETWORK_NAME}" > /dev/null

  # A self-signed leaf certificate. uv verifies TLS with rustls, which needs the
  # name in subjectAltName and rejects a CA certificate used as a server cert,
  # which is what openssl -x509 produces unless told otherwise.
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "${WORK_DIR}/key.pem" -out "${WORK_DIR}/cert.pem" \
    -subj "/CN=${MIRROR_NAME}" -addext "subjectAltName=DNS:${MIRROR_NAME}" \
    -addext "basicConstraints=critical,CA:FALSE" 2> /dev/null
  chmod 644 "${WORK_DIR}/key.pem"

  cat > "${WORK_DIR}/default.conf" <<'EOF'
server {
    listen 8080;
    listen 8443 ssl;
    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;
    proxy_ssl_server_name on;
    proxy_http_version 1.1;

    # The pypi.org simple index, with every download link rewritten from
    # files.pythonhosted.org to this server. Compression is disabled upstream
    # so sub_filter can see the body; both the HTML and the JSON (PEP 691)
    # forms that uv requests are rewritten.
    location /pypi/simple/ {
        proxy_pass https://pypi.org/simple/;
        proxy_set_header Host pypi.org;
        proxy_set_header Accept-Encoding "";
        sub_filter_types application/vnd.pypi.simple.v1+json application/vnd.pypi.simple.v1+html;
        sub_filter_once off;
        sub_filter "https://files.pythonhosted.org/" "$scheme://$http_host/pypi/files/";
    }

    location /pypi/files/ {
        proxy_pass https://files.pythonhosted.org/;
        proxy_set_header Host files.pythonhosted.org;
    }

    # An operator's private index that has none of the packages asked for
    location /private/simple/ {
        return 404;
    }
}
EOF
  docker run -d --name "${MIRROR_NAME}" --network "${NETWORK_NAME}" \
    -v "${WORK_DIR}/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "${WORK_DIR}/cert.pem:/etc/nginx/certs/cert.pem:ro" \
    -v "${WORK_DIR}/key.pem:/etc/nginx/certs/key.pem:ro" \
    "${MIRROR_IMAGE}" > /dev/null
  for _ in $(seq 1 30); do
    if docker exec "${MIRROR_NAME}" wget -q -O /dev/null "http://127.0.0.1:8080/pypi/simple/six/" 2> /dev/null; then
      echo "Indexes are up on ${MIRROR_NAME}:8080 and :8443"
      return
    fi
    sleep 1
  done
  echo "ERROR: the pypi.org proxy did not answer" >&2
  docker logs "${MIRROR_NAME}" >&2 || true
  exit 1
}

# Run a shell script in the operator image, with this checkout mounted over the
# image's openc3/bin and on the ruby load path, and the fixtures at /fixtures.
# Index settings an image may carry from a PYPI_URL build are cleared, so the
# arguments from PypiUrl.build_args are the only index configuration.
in_image() {
  docker run --rm --network "${NETWORK_NAME}" \
    -v "${REPO_ROOT}/openc3:/src:ro" \
    -v "${REPO_ROOT}/openc3/bin/uvinstall:/openc3/bin/uvinstall:ro" \
    -v "${REPO_ROOT}/openc3/bin/pipinstall:/openc3/bin/pipinstall:ro" \
    -v "${FIXTURES}:/fixtures" \
    -e HOME=/tmp \
    -e UV_DEFAULT_INDEX= -e UV_INDEX= -e UV_INDEX_URL= -e UV_INSECURE_HOST= \
    --entrypoint sh "$@"
}

# Build the fixtures: a generated --python plugin, packaged as a gem and
# unpacked the way plugin install unpacks it; the demo plugin with and without
# its lock; and unlocked plugins that point at their author's index.
build_fixtures() {
  echo "=== building fixtures"
  local demo="${REPO_ROOT}/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo"
  mkdir -p "${FIXTURES}/demo-locked" "${FIXTURES}/demo-unlocked"
  cp "${demo}/pyproject.toml" "${demo}/uv.lock" "${FIXTURES}/demo-locked/"
  cp "${demo}/pyproject.toml" "${FIXTURES}/demo-unlocked/"

  mkdir -p "${FIXTURES}/author-index" "${FIXTURES}/author-source" "${FIXTURES}/plain"
  cat > "${FIXTURES}/author-index/pyproject.toml" <<EOF
[project]
name = "author-index"
version = "0.0.0"
requires-python = ">=3.11"
dependencies = ["six"]

[tool.uv]
package = false
index = [{ name = "author", url = "${AUTHOR_INDEX}" }]
EOF
  cat > "${FIXTURES}/author-source/pyproject.toml" <<EOF
[project]
name = "author-source"
version = "0.0.0"
requires-python = ">=3.11"
dependencies = ["six"]

[tool.uv]
package = false
index = [{ name = "author", url = "${AUTHOR_INDEX}", explicit = true }]

[tool.uv.sources]
six = { index = "author" }
EOF
  cat > "${FIXTURES}/plain/pyproject.toml" <<EOF
[project]
name = "plain"
version = "0.0.0"
requires-python = ">=3.11"
dependencies = ["six"]

[tool.uv]
package = false
EOF

  chmod -R a+rwX "${FIXTURES}"
  in_image "${IMAGE}" -c '
    set -e
    mkdir -p /tmp/gen && cd /tmp/gen
    ruby -I/src/lib /src/bin/openc3cli generate plugin pyidx --python > /dev/null
    cd openc3-cosmos-pyidx
    sed -i "s/^dependencies = \[\]/dependencies = [\"six\"]/" pyproject.toml
    uv lock --quiet
    VERSION=0.0.1 gem build openc3-cosmos-pyidx.gemspec --quiet > /dev/null
    mkdir -p /fixtures/generated
    gem unpack openc3-cosmos-pyidx-0.0.1.gem --target /tmp/unpacked > /dev/null
    cp -r /tmp/unpacked/openc3-cosmos-pyidx-0.0.1/. /fixtures/generated/
    chmod -R a+rwX /fixtures
  '
}

RESULTS=()
FAILURES=0
pass() { RESULTS+=("PASS  $1"); }
fail() { RESULTS+=("FAIL  $1"); FAILURES=$((FAILURES + 1)); }

# run_case NAME EXPECT PYPI_URL FIXTURE [docker run args...]
#
# Runs uvinstall for FIXTURE with the index arguments PypiUrl.build_args gives
# for PYPI_URL, then imports the plugin's dependency from the venv. EXPECT is
# "pass" or "fail". The install log lands at ${LOG_DIR}/NAME.log and the
# mirror's access log for the case at ${LOG_DIR}/NAME.mirror.log.
run_case() {
  local name="$1" expect="$2" pypi_url="$3" fixture="$4" log status=0 before
  shift 4
  log="${LOG_DIR}/${name}.log"
  echo "--- ${name}"
  before="$(docker logs "${MIRROR_NAME}" 2>&1 | wc -l)"
  # shellcheck disable=SC2016 # expanded by the container shell
  in_image "$@" -e UV_CACHE_DIR=/tmp/uv-cache -e UVINSTALL_VENV_ROOT=/tmp/venvs \
    "${IMAGE}" -c '
    set -e
    pypi_url="$1"; fixture="$2"; module="$3"
    # One argument per line, so no argument may contain a newline
    ruby -I/src/lib -e "require %q(openc3/utilities/pypi_url); puts OpenC3::PypiUrl.build_args(ARGV[0])" "$pypi_url" > /tmp/args
    set --
    while IFS= read -r arg; do set -- "$@" "$arg"; done < /tmp/args
    echo "index args: $*"
    /openc3/bin/uvinstall "$fixture" "/fixtures/$fixture" "$@"
    "/tmp/venvs/$fixture/.venv/bin/python" -c "import $module; print(\"imported $module\")"
  ' sh "${pypi_url}" "${fixture}" "$(module_for "${fixture}")" > "${log}" 2>&1 || status=$?
  docker logs "${MIRROR_NAME}" 2>&1 | tail -n +"$((before + 1))" | grep -F '"GET ' > "${LOG_DIR}/${name}.mirror.log" || true

  if [[ "$expect" == "pass" && $status -eq 0 ]] || [[ "$expect" == "fail" && $status -ne 0 ]]; then
    pass "${name}"
  else
    fail "${name} (expected ${expect}, exited ${status}; see ${log})"
  fi
}

module_for() {
  case "$1" in
    demo-*) echo numpy ;;
    *) echo six ;;
  esac
}

# check_log NAME DESCRIPTION PATTERN [LOG] - PATTERN must appear in NAME's
# install log, or in its LOG (e.g. mirror.log)
check_log() {
  local name="$1" description="$2" pattern="$3" log="${LOG_DIR}/${1}.${4:-log}"
  if grep -qF -- "$pattern" "$log"; then
    pass "${name}: ${description}"
  else
    fail "${name}: ${description} (see ${log})"
  fi
}

# refute_log NAME DESCRIPTION PATTERN [LOG] - PATTERN must not appear
refute_log() {
  local name="$1" description="$2" pattern="$3" log="${LOG_DIR}/${1}.${4:-log}"
  if grep -qF -- "$pattern" "$log"; then
    fail "${name}: ${description} (see ${log})"
  else
    pass "${name}: ${description}"
  fi
}

run_cases() {
  echo "=== running installs in ${IMAGE}"

  # 1. Generated --python plugin with a committed uv.lock
  run_case generated-locked pass "${DEFAULT_INDEX}" generated
  check_log generated-locked "gem carries uv.lock" "Found uv.lock"
  check_log generated-locked "installed via uv sync --frozen" "uv sync --frozen succeeded"

  # 2. Demo plugin without the setuptools shim, locked and unlocked
  run_case demo-locked pass "${DEFAULT_INDEX}" demo-locked
  check_log demo-locked "installed via uv sync --frozen" "uv sync --frozen succeeded"
  run_case demo-unlocked pass "${DEFAULT_INDEX}" demo-unlocked
  check_log demo-unlocked "installed from pyproject.toml" "Installing from pyproject.toml via uv pip install"
  refute_log demo-unlocked "no build fallback needed" "Failed to build Python package"

  # 3. A designated index is authoritative over the plugin's own index config.
  # The default-pypi_url runs are the control: the author's index is reachable
  # and used, so the private-index failures come from --no-config/--no-sources.
  local fixture
  for fixture in author-index author-source; do
    run_case "${fixture}-default" pass "${DEFAULT_INDEX}" "${fixture}" "${BLOCKED_HOSTS[@]}"
    check_log "${fixture}-default" "resolved from the author's index" "GET /pypi/simple/six/" mirror.log
    run_case "${fixture}-private" fail "${PRIVATE_INDEX}" "${fixture}" "${BLOCKED_HOSTS[@]}"
    check_log "${fixture}-private" "private index queried" "GET /private/simple/six/" mirror.log
    refute_log "${fixture}-private" "author's index never queried" "GET /pypi/" mirror.log
  done

  # 4. Self-signed index
  run_case tls-no-opt-in fail "${TLS_INDEX}" plain "${BLOCKED_HOSTS[@]}"
  check_log tls-no-opt-in "rejected the certificate" "invalid peer certificate"
  run_case tls-allow-insecure-host pass "${TLS_INDEX}" plain "${BLOCKED_HOSTS[@]}" -e UV_ALLOW_INSECURE_HOST=1
  check_log tls-allow-insecure-host "--allow-insecure-host passed" "--allow-insecure-host ${MIRROR_NAME}"
  check_log tls-allow-insecure-host "downloaded from the index" "GET /pypi/files/" mirror.log
  run_case tls-deprecated-env pass "${TLS_INDEX}" plain "${BLOCKED_HOSTS[@]}" -e PIP_ENABLE_TRUSTED_HOST=1
  check_log tls-deprecated-env "--allow-insecure-host passed" "--allow-insecure-host ${MIRROR_NAME}"
}

report() {
  local line verdict="PASSED"
  [[ $FAILURES -gt 0 ]] && verdict="FAILED"
  echo ""
  echo "=== plugin pypi_url installs: ${verdict}"
  for line in "${RESULTS[@]}"; do echo "  ${line}"; done
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### plugin pypi_url installs: ${verdict}"
      for line in "${RESULTS[@]}"; do echo "- \`${line%% *}\` ${line#*  }"; done
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
  echo "ERROR: ${IMAGE} not found; build it with ./openc3.sh build or pass --image" >&2
  exit 1
fi

start_mirror
build_fixtures
run_cases
report
[[ $FAILURES -eq 0 ]]
