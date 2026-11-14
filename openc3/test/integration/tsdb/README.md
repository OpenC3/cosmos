# TSDB Integration Tests

End-to-end integration tests for QuestDB (TSDB) functionality. These tests verify that data can be written to and read from QuestDB correctly across both Python and Ruby implementations.

## Prerequisites

- Docker and Docker Compose
- Python 3.10+ with uv
- Ruby 3.1+ with Bundler

## Quick Start

1. Start QuestDB:

   ```bash
   docker compose -f docker-compose.test.yml up -d
   ```

   This starts two QuestDB containers. `questdb-shard1` (ports 9010 and 8822)
   acts as db_shard 1 for the cross-db_shard tests, which are skipped if it isn't
   running. Both use the same settings as the production `openc3-tsdb` image
   (see `openc3-tsdb/Dockerfile`), including `cairo.commit.mode=adaptive`.
   `QUESTDB_VERSION` and `QDB_CAIRO_COMMIT_MODE` override the image version and
   commit mode.

2. Wait for QuestDB to be ready (check http://localhost:9000)

3. Run Python tests:

   ```bash
   cd openc3/python
   uv run pytest ../test/integration/tsdb/python/ -v
   ```

4. Run Ruby tests:

   ```bash
   cd openc3/test/integration/tsdb/ruby
   bundle install
   bundle exec rspec . -fd
   ```

5. Stop QuestDB:
   ```bash
   docker compose -f docker-compose.test.yml down
   ```

## Test Structure

```
tsdb/
├── docker-compose.test.yml   # QuestDB container for testing
├── conftest.py               # Python pytest fixtures
├── helpers/
│   └── questdb_writer.py     # Python helper for cross-language tests
├── python/
│   ├── test_tsdb_roundtrip.py # Python roundtrip tests
│   └── test_tsdb_lookup_db_shards.py # Cross-db_shard lookup tests
└── ruby/
    ├── spec_helper.rb        # RSpec configuration
    ├── cvt_model_tsdb_spec.rb # CvtModel tests
    ├── logged_streaming_thread_tsdb_spec.rb # Streaming API tests
    └── tsdb_lookup_db_shards_spec.rb # Cross-db_shard lookup tests
```

## What's Tested

### Python Tests (`python/test_tsdb_roundtrip.py`)

- INT (signed) roundtrip: 3-bit to 64-bit
- UINT (unsigned) roundtrip: 3-bit to 64-bit
- FLOAT roundtrip: 32-bit and 64-bit
- STRING roundtrip
- BLOCK (binary) roundtrip
- DERIVED roundtrip (int, float, string)
- ARRAY roundtrip (numeric, string, mixed)
- OBJECT roundtrip (simple and complex)

### Ruby CvtModel Tests (`ruby/cvt_model_tsdb_spec.rb`)

Cross-language tests where Python writes data and Ruby reads it back:

- Same data types as Python tests
- Tests RAW, CONVERTED, and FORMATTED value types
- Verifies `CvtModel.tsdb_lookup` functionality

### Cross-db_shard Tests (`python/test_tsdb_lookup_db_shards.py`, `ruby/tsdb_lookup_db_shards_spec.rb`)

`tsdb_lookup` with targets on different db_shards (separate QuestDB instances):

- Range rows from each db_shard are aligned by packet time to the db_shard of the first item
- A point in time returns the last row before start_time from each db_shard

Production resolves each db_shard by hostname (`SHARDNUM` in `OPENC3_TSDB_HOSTNAME`).
Locally both run on 127.0.0.1 so the tests select db_shard 1 by the
`OPENC3_TSDB_SHARD1_INGEST_PORT` and `OPENC3_TSDB_SHARD1_QUERY_PORT` ports.

### Ruby Streaming Tests (`ruby/logged_streaming_thread_tsdb_spec.rb`)

- `LoggedStreamingThread.stream_items` functionality
- INT, FLOAT, STRING, DERIVED, ARRAY streaming
- CONVERTED and FORMATTED value streaming
- Timestamp handling
- Multiple items from same packet
- Completion detection (end_time behavior)

### Ingest Protocol

`QuestDBClient` ingests over QWP (QuestDB Wire Protocol, WebSocket) by default.
Set `OPENC3_TSDB_INGEST_PROTOCOL=http` to run the tests over ILP/HTTP instead.

### Benchmarks (`python/test_perf_ingest.py`)

Ingest and query benchmarks for comparing QuestDB versions, ingest protocols
and commit modes. They're skipped unless `OPENC3_TSDB_PERF=1`. `helpers/run_perf.sh`
starts a fresh QuestDB for each run and labels the results, which are appended to
`perf_results.jsonl` (gitignored). `helpers/compare_perf.py` tabulates them:

```bash
cd openc3/test/integration/tsdb
helpers/run_perf.sh 10.2.0-ws-nosync 10.2.0 nosync 3
helpers/run_perf.sh 10.2.0-ws-adaptive 10.2.0 adaptive 3
OPENC3_TSDB_INGEST_PROTOCOL=http helpers/run_perf.sh 10.2.0-http-adaptive 10.2.0 adaptive 3
cd ../../../python
uv run python ../test/integration/tsdb/helpers/compare_perf.py
```

Run them on hardware like the deployment's: adaptive commit mode flushes to disk
on every commit, so its cost depends heavily on the disk (and is much higher
under Docker Desktop on macOS than on Linux).

`QDB_*` variables are passed to the server and `OPENC3_TSDB_PERF_BATCH_SIZE` sets
the client batch size, e.g.
`QDB_CAIRO_ADAPTIVE_COMMIT_GROUP_WINDOW=500ms helpers/run_perf.sh w500 10.2.0 adaptive 3`.
Adaptive mode's cost is a WAL file flush per column file of each commit, so it
scales with the number of commits. Measured with QuestDB 10.2.0 (Docker Desktop on
macOS):

- `cairo.adaptive.commit.group.window` (0, 50ms, 500ms) and
  `cairo.wal.commit.writeback.drain` made no difference: the window only batches
  the sequencer flush, which isn't on the acknowledgement path when nonzero.
- Fewer, larger commits made the difference: 5000 row batches instead of 500
  doubled adaptive throughput, matching nosync for a single wide table. So
  `QuestDBClient` flushes every 5000 rows, or 500k values for wide packets.
- Raising the QWP frame cap (`QDB_HTTP_RECV_BUFFER_SIZE`, 2 MB) didn't help
  further; batches over the cap are sent as several frames.

## CI/CD

These tests run in the `tsdb_integration_tests.yml` GitHub Action workflow which:

1. Starts QuestDB with `docker-compose.test.yml`
2. Runs Python tests
3. Runs Ruby tests
4. Reports results

The workflow only runs on changes to TSDB-related files.

## Troubleshooting

### QuestDB not available

Ensure QuestDB is running and accessible:

```bash
curl http://localhost:9000/
psql -h localhost -p 8812 -U admin -d qdb
```

### Connection refused

Check that ports 9000 (HTTP) and 8812 (PostgreSQL) are not in use:

```bash
lsof -i :9000
lsof -i :8812
```

### Tests timing out

QuestDB has eventual consistency. If tests fail with timing issues, try increasing the `timeout` parameter in `wait_for_data()` calls.
