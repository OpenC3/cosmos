# TSDB Integration Tests

End-to-end integration tests for QuestDB (TSDB) functionality. These tests verify that data can be written to and read from QuestDB correctly across both Python and Ruby implementations.

## Prerequisites

- Docker and Docker Compose
- Python 3.11+ with Poetry
- Ruby 3.1+ with Bundler

## Quick Start

1. Start QuestDB:

   ```bash
   docker compose -f docker-compose.test.yml up -d
   ```

2. Wait for QuestDB to be ready (check http://localhost:9000)

3. Run Python tests:

   ```bash
   cd openc3/python
   poetry run pytest ../test/integration/tsdb/python/ -v
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
│   └── test_tsdb_roundtrip.py # Python roundtrip tests
└── ruby/
    ├── spec_helper.rb        # RSpec configuration
    ├── cvt_model_tsdb_spec.rb # CvtModel tests
    └── logged_streaming_thread_tsdb_spec.rb # Streaming API tests
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

### Ruby Streaming Tests (`ruby/logged_streaming_thread_tsdb_spec.rb`)

- `LoggedStreamingThread.stream_items` functionality
- INT, FLOAT, STRING, DERIVED, ARRAY streaming
- CONVERTED and FORMATTED value streaming
- Timestamp handling
- Multiple items from same packet
- Completion detection (end_time behavior)

## CI/CD

These tests run in the `tsdb_integration_tests.yml` GitHub Action workflow which:

1. Starts a QuestDB service container
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
