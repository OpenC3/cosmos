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

# Run the TSDB benchmarks (python/test_perf_ingest.py) against a freshly
# started QuestDB so runs don't affect each other.
#
# Usage: helpers/run_perf.sh <label> <questdb_version> <commit_mode> [runs] [pytest args...]
#   e.g. helpers/run_perf.sh 9.4.3-http-nosync 9.4.3 nosync 3
#        OPENC3_TSDB_INGEST_PROTOCOL=ws helpers/run_perf.sh 10.2.0-ws-adaptive 10.2.0 adaptive 3
#
# Other OPENC3_TSDB_* variables (OPENC3_TSDB_PERF_ROWS, OPENC3_TSDB_INGEST_PROTOCOL,
# ...) pass through to the test. QDB_* variables pass through to the QuestDB
# server to try other settings, e.g.
#   QDB_CAIRO_ADAPTIVE_COMMIT_GROUP_WINDOW=500ms helpers/run_perf.sh window-500ms 10.2.0 adaptive 3
# Results go to perf_results.jsonl, compare them with:
#   uv run python ../test/integration/tsdb/helpers/compare_perf.py
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <label> <questdb_version> <commit_mode> [runs] [pytest args...]" >&2
  exit 1
fi
LABEL=$1
VERSION=$2
COMMIT_MODE=$3
shift 3
# The run count is optional, anything after it is passed to pytest, e.g. -k back_orbit
RUNS=1
if [[ $# -gt 0 && $1 =~ ^[0-9]+$ ]]; then
  RUNS=$1
  shift
fi

TSDB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_DIR="$(cd "$TSDB_DIR/../../../python" && pwd)"
COMPOSE=(docker compose -f "$TSDB_DIR/docker-compose.test.yml")

# Pass QDB_* server settings through with a compose override
# (the commit mode comes from the command line)
OVERRIDE=$(mktemp "${TMPDIR:-/tmp}/questdb-perf-override.XXXXXX")
trap 'rm -f "$OVERRIDE"' EXIT
{
  echo "services:"
  echo "  questdb:"
  echo "    environment:"
  echo "      QDB_CAIRO_COMMIT_MODE: \"$COMMIT_MODE\""
  while IFS='=' read -r name value; do
    [[ "$name" == "QDB_CAIRO_COMMIT_MODE" ]] && continue
    echo "      $name: \"$value\""
  done < <(env | grep '^QDB_' || true)
} > "$OVERRIDE"
COMPOSE+=(-f "$OVERRIDE")

for run in $(seq 1 "$RUNS"); do
  echo "=== $LABEL (QuestDB $VERSION, commit mode $COMMIT_MODE) run $run/$RUNS"
  # Recreate without volumes so each run starts from an empty database
  "${COMPOSE[@]}" rm -sf questdb > /dev/null
  QUESTDB_VERSION=$VERSION "${COMPOSE[@]}" up -d --wait questdb
  (
    cd "$PYTHON_DIR"
    OPENC3_TSDB_PERF=1 OPENC3_TSDB_PERF_LABEL="$LABEL" \
      uv run pytest "$TSDB_DIR/python/test_perf_ingest.py" -v -s -p no:cacheprovider "$@"
  )
done
