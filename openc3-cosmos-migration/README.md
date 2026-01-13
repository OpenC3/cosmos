# OpenC3 COSMOS Migration Microservice

A Python microservice for migrating historical COSMOS decommutated telemetry data from bin files into QuestDB time-series database.

## Overview

This microservice reads COSMOS5 binary packet log files (decom_logs) from S3-compatible storage and ingests the decommutated telemetry data into QuestDB for historical analysis and trending.

### Key Features

- Parses COSMOS5 binary packet log format (`.bin` and `.bin.gz` files)
- Extracts JSON-encoded decommutated telemetry from packet logs
- Ingests data into QuestDB via ILP HTTP protocol
- Processes files in reverse chronological order (newest first)
- Tracks progress in Redis for resume capability
- Rate-limits ingestion to avoid overwhelming operational systems

## Architecture

```
S3/MinIO Logs Bucket          Migration Microservice              QuestDB
┌─────────────────────┐       ┌─────────────────────────┐       ┌──────────────┐
│ {scope}/decom_logs/ │       │                         │       │              │
│   ├── tlm/          │──────>│  1. List files (desc)   │       │              │
│   │   ├── INST/     │       │  2. Download .bin.gz    │       │  TARGET__    │
│   │   └── ...       │       │  3. Decompress          │──────>│  PACKET_NAME │
│   └── cmd/          │       │  4. Parse JSON packets  │       │  tables      │
│                     │       │  5. Batch ingest        │       │              │
└─────────────────────┘       └─────────────────────────┘       └──────────────┘
```

## COSMOS Data Type to QuestDB Type Mapping

| COSMOS Type | Bit Size | QuestDB Type | Notes |
|-------------|----------|--------------|-------|
| INT | 8/16/32 | int | Signed integers |
| INT | 64 | long | 64-bit signed |
| INT | 3, 13 (bitfield) | int | Bitfields fit in int |
| UINT | 8/16 | int | Fits in signed int |
| UINT | 32 | long | Needs 33 bits for full range |
| UINT | 64 | varchar | Exceeds signed long range |
| FLOAT | 32 | float | IEEE 754 single precision |
| FLOAT | 64 | double | IEEE 754 double precision |
| STRING | var | varchar | Variable-length text |
| BLOCK | var | varchar | Base64-encoded binary |
| BOOL | N/A | boolean | Native boolean |
| ARRAY | var | double[] | Numeric arrays; else JSON |
| OBJECT | var | varchar | JSON-serialized |
| ANY | var | varchar | JSON-serialized |

### Important Limitations

- QuestDB does NOT support IEEE 754 special values (`Infinity`, `-Infinity`, `NaN`) - these become `NULL`
- Integer `MIN_VALUE` is used as NULL sentinel in QuestDB

## Prerequisites

- Python 3.10+
- Docker (for QuestDB integration testing)
- Poetry

## Installation

The migration microservice depends on the `openc3` Python package. Install using Poetry:

```bash
# From the cosmos repository root, install the openc3 package
cd openc3/python
poetry install

# Install test dependencies (pytest, psycopg, questdb are included in openc3)
# Tests are run from the openc3/python poetry environment
```

## Running Tests

All tests are run using the `openc3/python` Poetry environment.

### Unit Tests (No QuestDB Required)

Run the bin file processor tests:

```bash
cd openc3/python
poetry run pytest ../../openc3-cosmos-migration/tests/test_bin_file_processor.py -v
```

### Integration Tests (Requires QuestDB)

1. Start the QuestDB test container:

```bash
cd openc3-cosmos-migration
docker compose -f docker-compose.test.yml up -d
```

2. Wait for QuestDB to be healthy (about 10 seconds):

```bash
docker compose -f docker-compose.test.yml ps
# Should show "healthy" status
```

3. Run the integration tests:

```bash
cd openc3/python
poetry run pytest ../../openc3-cosmos-migration/tests/test_questdb_integration.py -v
```

4. Stop QuestDB when done:

```bash
cd openc3-cosmos-migration
docker compose -f docker-compose.test.yml down
```

### Running All Tests

```bash
# Start QuestDB
cd openc3-cosmos-migration
docker compose -f docker-compose.test.yml up -d
sleep 10

# Run all tests from openc3/python
cd ../openc3/python
poetry run pytest ../../openc3-cosmos-migration/ -v

# Stop QuestDB
cd ../../openc3-cosmos-migration
docker compose -f docker-compose.test.yml down
```

## Configuration

The microservice uses the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENC3_TSDB_HOSTNAME` | QuestDB hostname | Required |
| `OPENC3_TSDB_INGEST_PORT` | HTTP ILP ingest port | 9000 |
| `OPENC3_TSDB_QUERY_PORT` | PostgreSQL wire protocol port | 8812 |
| `OPENC3_TSDB_USERNAME` | QuestDB username | Required |
| `OPENC3_TSDB_PASSWORD` | QuestDB password | Required |
| `MIGRATION_ENABLED` | Enable migration processing | false |
| `MIGRATION_BATCH_SIZE` | Packets per batch | 1000 |
| `MIGRATION_SLEEP_SECONDS` | Sleep between batches | 0.5 |

## File Structure

```
openc3-cosmos-migration/
├── README.md                    # This file
├── docker-compose.test.yml      # QuestDB container for testing
├── migration_microservice.py    # Main microservice class
├── bin_file_processor.py        # Bin file parsing logic
└── tests/
    ├── conftest.py              # Pytest fixtures for QuestDB
    ├── test_bin_file_processor.py   # Unit tests for bin processor
    └── test_questdb_integration.py  # Integration tests for all COSMOS types
```

## Related Components

- `openc3/python/openc3/utilities/questdb_client.py` - Shared QuestDB client
- `openc3/python/openc3/logs/packet_log_reader.py` - Binary packet log parser
- `openc3/python/openc3/logs/packet_log_writer.py` - Binary packet log writer
- `openc3/python/openc3/packets/json_packet.py` - JSON packet representation
