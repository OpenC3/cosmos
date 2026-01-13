# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Pytest fixtures for QuestDB integration tests.

Usage:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: pytest tests/test_questdb_integration.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import os
import sys
import time
import pytest

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "openc3", "python"))

# Set environment variables for QuestDB connection (test defaults)
os.environ.setdefault("OPENC3_TSDB_HOSTNAME", "127.0.0.1")
os.environ.setdefault("OPENC3_TSDB_INGEST_PORT", "9000")
os.environ.setdefault("OPENC3_TSDB_QUERY_PORT", "8812")
os.environ.setdefault("OPENC3_TSDB_USERNAME", "admin")
os.environ.setdefault("OPENC3_TSDB_PASSWORD", "admin")

from openc3.utilities.questdb_client import QuestDBClient


def is_questdb_available():
    """Check if QuestDB is available for testing."""
    try:
        import psycopg

        conn = psycopg.connect(
            host=os.environ.get("OPENC3_TSDB_HOSTNAME", "127.0.0.1"),
            port=int(os.environ.get("OPENC3_TSDB_QUERY_PORT", "8812")),
            user=os.environ.get("OPENC3_TSDB_USERNAME", "admin"),
            password=os.environ.get("OPENC3_TSDB_PASSWORD", "admin"),
            dbname="qdb",
            autocommit=True,
            connect_timeout=2,
        )
        conn.close()
        return True
    except Exception:
        return False


# Skip marker for tests requiring QuestDB
requires_questdb = pytest.mark.skipif(not is_questdb_available(), reason="QuestDB not available")


@pytest.fixture(scope="session")
def questdb_available():
    """Session-scoped fixture to check QuestDB availability."""
    if not is_questdb_available():
        pytest.skip("QuestDB not available. Run: docker compose -f docker-compose.test.yml up -d")
    return True


@pytest.fixture
def questdb_client(questdb_available):
    """
    Fixture providing a connected QuestDB client.

    Automatically cleans up connections after test.
    """
    client = QuestDBClient()
    client.connect_ingest()
    client.connect_query()
    yield client
    client.close()


@pytest.fixture
def clean_table(questdb_client):
    """
    Fixture factory for creating and cleaning up test tables.

    Usage:
        def test_something(clean_table):
            table_name = clean_table("TEST__TABLE")
            # ... use table ...
    """
    created_tables = []

    def _clean_table(table_name):
        # Drop table if exists (for clean test state)
        try:
            with questdb_client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
        except Exception:
            pass
        created_tables.append(table_name)
        return table_name

    yield _clean_table

    # Cleanup: drop all created tables
    for table_name in created_tables:
        try:
            with questdb_client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
        except Exception:
            pass


@pytest.fixture
def wait_for_data():
    """
    Fixture to wait for data to be visible in QuestDB.

    QuestDB has eventual consistency - data may not be immediately visible after write.
    """

    def _wait(questdb_client, table_name, expected_count, timeout=5.0):
        """Wait for table to have expected number of rows."""
        start = time.time()
        while time.time() - start < timeout:
            try:
                with questdb_client.query.cursor() as cur:
                    cur.execute(f'SELECT count() FROM "{table_name}"')
                    count = cur.fetchone()[0]
                    if count >= expected_count:
                        return count
            except Exception:
                pass
            time.sleep(0.1)
        return 0

    return _wait
