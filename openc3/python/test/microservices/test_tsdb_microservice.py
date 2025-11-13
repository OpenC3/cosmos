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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import re
import json
import base64
import unittest
from datetime import datetime, timezone
import time
import math
from unittest.mock import Mock, patch
from test.test_helper import mock_redis, setup_system, capture_io, System
from openc3.models.target_model import TargetModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.microservices.tsdb_microservice import TsdbMicroservice
from openc3.topics.topic import Topic
from openc3.topics.config_topic import ConfigTopic
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from questdb.ingress import IngressError, TimestampMicros, TimestampNanos


class TestTsdbMicroservice(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        setup_system()

        # Set up required environment variables
        os.environ["OPENC3_SCOPE"] = "DEFAULT"
        os.environ["OPENC3_TSDB_HOSTNAME"] = "localhost"
        os.environ["OPENC3_TSDB_INGEST_PORT"] = "9009"
        os.environ["OPENC3_TSDB_QUERY_PORT"] = "8812"
        os.environ["OPENC3_TSDB_USERNAME"] = "admin"
        os.environ["OPENC3_TSDB_PASSWORD"] = "quest"

        # Create test targets
        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(name="SYSTEM", scope="DEFAULT")
        model.create()

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

    def tearDown(self):
        # Clean up environment variables
        for var in [
            "OPENC3_TSDB_HOSTNAME",
            "OPENC3_TSDB_INGEST_PORT",
            "OPENC3_TSDB_QUERY_PORT",
            "OPENC3_TSDB_USERNAME",
            "OPENC3_TSDB_PASSWORD",
        ]:
            if var in os.environ:
                del os.environ[var]

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_initialization_success(self, mock_system, mock_psycopg, mock_sender):
        """Test successful initialization of TsdbMicroservice"""
        # Setup mocks
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Create microservice model
        model = MicroserviceModel(
            "DEFAULT__TSDB__INST",
            scope="DEFAULT",
            topics=[
                "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            ],
            target_names=["INST"],
        )
        model.create()

        # Initialize microservice
        tsdb = TsdbMicroservice("DEFAULT__TSDB__INST")

        # Verify connections were established
        self.assertIsNotNone(tsdb.ingest)
        self.assertIsNotNone(tsdb.query)
        mock_ingest.establish.assert_called_once()

        # Verify table creation was attempted
        mock_cursor.execute.assert_called()

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_missing_hostname_env_var(self, mock_system, mock_psycopg, mock_sender):
        """Test initialization fails with missing OPENC3_TSDB_HOSTNAME"""
        del os.environ["OPENC3_TSDB_HOSTNAME"]

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(RuntimeError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("missing env var OPENC3_TSDB_HOSTNAME", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_missing_ingest_port_env_var(self, mock_system, mock_psycopg, mock_sender):
        """Test initialization fails with missing OPENC3_TSDB_INGEST_PORT"""
        del os.environ["OPENC3_TSDB_INGEST_PORT"]

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(RuntimeError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("missing env var OPENC3_TSDB_INGEST_PORT", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_missing_username_env_var(self, mock_system, mock_psycopg, mock_sender):
        """Test initialization fails with missing OPENC3_TSDB_USERNAME"""
        del os.environ["OPENC3_TSDB_USERNAME"]

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(RuntimeError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("missing env var OPENC3_TSDB_USERNAME", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_missing_password_env_var(self, mock_system, mock_psycopg, mock_sender):
        """Test initialization fails with missing OPENC3_TSDB_PASSWORD"""
        del os.environ["OPENC3_TSDB_PASSWORD"]

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(RuntimeError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("missing env var OPENC3_TSDB_PASSWORD", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_ingest_connection_failure(self, mock_system, mock_psycopg, mock_sender):
        """Test handling of ingest connection failure"""
        mock_sender.side_effect = Exception("Connection refused")

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(ConnectionError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("Failed to connect to TSDB", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_query_connection_failure(self, mock_system, mock_psycopg, mock_sender):
        """Test handling of query connection failure"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_psycopg.side_effect = Exception("Connection refused")

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        with self.assertRaises(ConnectionError) as context:
            TsdbMicroservice("DEFAULT__TSDB__TEST")

        self.assertIn("Failed to connect to TSDB", str(context.exception))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_with_valid_name(self, mock_system, mock_psycopg, mock_sender):
        """Test creating a table with a valid name"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Check that table was created with correct name
        calls = mock_cursor.execute.call_args_list
        self.assertTrue(any("INST__HEALTH_STATUS" in str(call) for call in calls))

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_with_invalid_characters(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test creating a table with invalid characters in the name"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Mock get_tlm to return a dummy packet
        mock_packet = Mock()
        mock_packet.sorted_items = []  # Empty list for test
        mock_get_tlm.return_value = mock_packet

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__TEST?PKT:1"],
            target_names=["INST"],
        )
        model.create()

        for stdout in capture_io():
            tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")
            # Should warn about invalid characters
            self.assertIn("changed to", stdout.getvalue())

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_creates_all_packet_items(self, mock_system, mock_psycopg, mock_sender):
        """Test that all items from a packet are stored as columns in the table"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify that CREATE TABLE was called with all packet items
        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0, "CREATE TABLE should have been called")

        # Get the CREATE TABLE SQL statement
        create_table_sql = str(create_table_calls[0])
        print("CREATE TABLE SQL:", create_table_sql.split("\n"))
        self.assertIn("timestamp timestamp", create_table_sql)
        self.assertIn("tag SYMBOL", create_table_sql)
        self.assertIn("PACKET_TIMESECONDS timestamp", create_table_sql)
        self.assertIn("RECEIVED_TIMESECONDS timestamp", create_table_sql)
        self.assertIn("PACKET_TIMEFORMATTED varchar", create_table_sql)
        self.assertIn("RECEIVED_TIMEFORMATTED varchar", create_table_sql)
        self.assertIn('"CCSDSTYPE" int', create_table_sql)
        # TIMESEC is 32 bits so upgraded to long
        self.assertIn('"TIMESEC" long', create_table_sql)
        self.assertIn('"ARY" array', create_table_sql)
        # Block of 80 bits becomes encoded varchar
        self.assertIn('"BLOCKTEST" varchar', create_table_sql)
        self.assertIn('"BRACKET[0]" int', create_table_sql)
        # Even a single bit is an int column
        self.assertIn('"1BIT" int', create_table_sql)
        # 63 bits is a long
        self.assertIn('"63BITS" long', create_table_sql)
        # 64 bits is a long256 because it can't fit in int64
        self.assertIn('"64BITS" long', create_table_sql)
        self.assertNotIn("DERIVED_GENERIC", create_table_sql)

        # Build expected items list from the packet
        expected_items = set()
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        for item in packet.sorted_items:
            # Sanitize item name the same way tsdb_microservice does
            sanitized_name = re.sub(r'[?\.,\'"\\/:)(+\-*%~;]', "_", item.name)
            if item.data_type != "DERIVED":
                expected_items.add(sanitized_name)

        # Verify that key items are in the CREATE TABLE statement
        for item_name in expected_items:

            self.assertIn(item_name, create_table_sql, f"Expected item '{item_name}' to be in CREATE TABLE statement")

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_is_printable(self, mock_system, mock_psycopg, mock_sender):
        """Test _is_printable method"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=[],
            target_names=[],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Test various strings
        self.assertTrue(tsdb._is_printable("Hello World"))
        self.assertTrue(tsdb._is_printable("123 456"))
        self.assertTrue(tsdb._is_printable("Test\nWith\nNewlines"))
        self.assertFalse(tsdb._is_printable("\x00\x01\x02"))

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.tsdb_microservice.get_all_tlm_names")
    @patch("openc3.microservices.microservice.System")
    def test_sync_topics_creates_new_target(
        self, mock_system, mock_get_all_tlm, mock_psycopg, mock_sender, mock_get_tlm
    ):
        """Test sync_topics creates tables for new targets"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)
        mock_get_all_tlm.return_value = ["PACKET1", "PACKET2"]
        # Mock get_tlm to return a dummy packet
        mock_packet = Mock()
        mock_packet.sorted_items = []  # Empty list for test
        mock_get_tlm.return_value = mock_packet

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=[],
            target_names=[],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")
        initial_topic_count = len(tsdb.topics)

        # Write a config event for a new target
        ConfigTopic.write({"type": "target", "kind": "created", "name": "NEWTARGET"}, scope="DEFAULT")

        tsdb.sync_topics()

        # Should have added new topics
        self.assertGreater(len(tsdb.topics), initial_topic_count)
        self.assertTrue(any("NEWTARGET" in topic for topic in tsdb.topics))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_sync_topics_deletes_target(self, mock_system, mock_psycopg, mock_sender):
        """Test sync_topics removes topics when target is deleted"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")
        initial_topics = tsdb.topics.copy()

        # Write a config event for deleting a target
        ConfigTopic.write({"type": "target", "kind": "deleted", "name": "INST"}, scope="DEFAULT")

        tsdb.sync_topics()

        # Should have removed INST topics
        self.assertFalse(any("{INST}" in topic for topic in tsdb.topics))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_integer_values(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles integer values correctly"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            result = orig_xread(*args, **kwargs)
            return result

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data
        json_data = {"TEMP1": 42, "TEMP2": 100}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify data was written to QuestDB
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertEqual(call_args[0][0], "INST__HEALTH_STATUS")
        self.assertIn("TEMP1", call_args[1]["columns"])
        self.assertEqual(call_args[1]["columns"]["TEMP1"], 42)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_large_integers(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics clamps large integers to int64 range"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with very large integer
        json_data = {"BIGVAL": 2**64, "SMALLVAL": -(2**64)}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify values were clamped
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertEqual(call_args[1]["columns"]["BIGVAL"], 2**63 - 1)
        self.assertEqual(call_args[1]["columns"]["SMALLVAL"], -(2**63) + 1)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_float_values(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles float values including NaN and Infinity"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with special float values
        json_data = {
            "TEMP1": 3.14,
            "TEMP2": {"json_class": "Float", "raw": "NaN"},
            "TEMP3": {"json_class": "Float", "raw": "Infinity"},
        }
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify float values were handled
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertEqual(call_args[1]["columns"]["TEMP1"], 3.14)
        self.assertTrue(math.isnan(call_args[1]["columns"]["TEMP2"]))
        self.assertTrue(math.isinf(call_args[1]["columns"]["TEMP3"]))

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_bytes_values(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics converts bytes to base64"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with bytes (encoded as String with raw list)
        test_bytes = [72, 101, 108, 108, 111]  # "Hello"
        json_data = {"DATA": {"json_class": "String", "raw": test_bytes}}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify bytes were converted to base64
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        expected = base64.b64encode(bytes(test_bytes)).decode("ascii")
        self.assertEqual(call_args[1]["columns"]["DATA"], expected)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_numeric_arrays(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics converts numeric lists to numpy arrays"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with numeric array
        json_data = {"ARRAY": [1.0, 2.0, 3.0, 4.0]}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify list was converted to numpy array
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        result = call_args[1]["columns"]["ARRAY"]
        # Check it's a numpy array by checking for the ndarray type
        import numpy

        self.assertIsInstance(result, numpy.ndarray)
        self.assertEqual(list(result), [1.0, 2.0, 3.0, 4.0])

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_non_numeric_arrays(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics converts non-numeric lists to JSON strings"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with non-numeric array
        json_data = {"STRARRAY": ["a", "b", "c"]}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify list was converted to JSON string
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertEqual(call_args[1]["columns"]["STRARRAY"], '["a", "b", "c"]')

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_timestamp_columns(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics converts PACKET_TIMESECONDS and RECEIVED_TIMESECONDS"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with timestamp columns
        current_time = time.time()
        json_data = {
            "PACKET_TIMESECONDS": current_time,
            "RECEIVED_TIMESECONDS": current_time + 1,
            "TEMP1": 100,
        }
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify timestamps were converted to TimestampMicros
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertIsInstance(call_args[1]["columns"]["PACKET_TIMESECONDS"], TimestampMicros)
        self.assertIsInstance(call_args[1]["columns"]["RECEIVED_TIMESECONDS"], TimestampMicros)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_invalid_item_names(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics sanitizes item names with invalid characters"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Write test data with invalid characters in item names
        json_data = {"TEMP?1": 100, "VALUE:2": 200, "DATA+3": 300}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        # Verify item names were sanitized
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        columns = call_args[1]["columns"]
        self.assertIn("TEMP_1", columns)
        self.assertIn("VALUE_2", columns)
        self.assertIn("DATA_3", columns)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_cast_error(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles type cast errors by altering table"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Setup mock to raise IngressError on first call, succeed on second
        error_msg = (
            "error in line 1: table: INST__HEALTH_STATUS, column: TEMP1; "
            'cast error from protocol type: FLOAT to column type: LONG","line":1'
        )
        mock_ingest.row.side_effect = [IngressError(1, error_msg), None]

        # Write test data
        json_data = {"TEMP1": 3.14}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        for stdout in capture_io():
            tsdb.read_topics()
            # Should have logged ALTER TABLE command
            self.assertIn("ALTER TABLE", stdout.getvalue())

        # Should have called row twice (failed, then succeeded)
        self.assertEqual(mock_ingest.row.call_count, 2)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_ingress_error(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles non-recoverable IngressError"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Setup mock to raise IngressError
        mock_ingest.row.side_effect = IngressError(1, "Unknown error")

        # Write test data
        json_data = {"TEMP1": 100}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        for stdout in capture_io():
            tsdb.read_topics()
            # Should have logged error
            self.assertIn("Error writing to QuestDB", stdout.getvalue())

        # Should have set error
        self.assertIsNotNone(tsdb.error)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_run_loop_handles_exceptions(self, mock_system, mock_psycopg, mock_sender):
        """Test run loop handles exceptions gracefully"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=[],
            target_names=[],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Mock read_topics to raise exception once then cancel
        call_count = [0]

        def side_effect():
            call_count[0] += 1
            if call_count[0] == 1:
                raise RuntimeError("Test error")
            tsdb.cancel_thread = True

        with patch.object(tsdb, "read_topics", side_effect=side_effect):
            for stdout in capture_io():
                tsdb.run()
                # Should have logged the error
                self.assertIn("Microservice error", stdout.getvalue())
                self.assertIn("Test error", stdout.getvalue())

        # Should have set error
        self.assertIsNotNone(tsdb.error)

    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_skips_unknown_target(self, mock_system, mock_psycopg, mock_sender):
        """Test initialization skips UNKNOWN target topics"""
        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=[
                "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
                "DEFAULT__DECOM__{UNKNOWN}__PKT",
            ],
            target_names=["INST", "UNKNOWN"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify table creation was not attempted for UNKNOWN
        calls = mock_cursor.execute.call_args_list
        self.assertFalse(any("UNKNOWN" in str(call) for call in calls))

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.microservices.tsdb_microservice.Sender")
    @patch("openc3.microservices.tsdb_microservice.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_stores_all_packet_items(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that all items from a packet are stored as columns in the table"""
        # Create a mock packet with sorted_items
        mock_item1 = Mock()
        mock_item1.name = "TEMP1"
        mock_item1.data_type = "FLOAT"

        mock_item2 = Mock()
        mock_item2.name = "TEMP2"
        mock_item2.data_type = "FLOAT"

        mock_item3 = Mock()
        mock_item3.name = "TEMP3"
        mock_item3.data_type = "FLOAT"

        mock_item4 = Mock()
        mock_item4.name = "TEMP4"
        mock_item4.data_type = "FLOAT"

        mock_item5 = Mock()
        mock_item5.name = "COLLECTS"
        mock_item5.data_type = "UINT"

        mock_item6 = Mock()
        mock_item6.name = "ASCIICMD"
        mock_item6.data_type = "STRING"

        mock_item7 = Mock()
        mock_item7.name = "ARY"
        mock_item7.data_type = "BLOCK"

        mock_item8 = Mock()
        mock_item8.name = "GROUND1STATUS"
        mock_item8.data_type = "UINT"

        mock_item9 = Mock()
        mock_item9.name = "BLOCKTEST"
        mock_item9.data_type = "BLOCK"

        packet = Mock()
        packet.sorted_items = [
            mock_item1,
            mock_item2,
            mock_item3,
            mock_item4,
            mock_item5,
            mock_item6,
            mock_item7,
            mock_item8,
            mock_item9,
        ]

        # Mock get_tlm to return this packet
        mock_get_tlm.return_value = packet

        mock_ingest = Mock()
        mock_sender.return_value = mock_ingest
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        orig_xread = self.redis.xread

        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            return orig_xread(*args, **kwargs)

        self.redis.xread = Mock(side_effect=xread_side_effect)

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify that CREATE TABLE was called with all packet items
        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0, "CREATE TABLE should have been called")

        # Get the CREATE TABLE SQL statement
        create_table_sql = str(create_table_calls[0])

        # Build expected items list from the packet
        expected_items = set()
        for item in packet.sorted_items:
            # Sanitize item name the same way tsdb_microservice does
            sanitized_name = re.sub(r'[?\.,\'"\\/:)(+\-*%~;]', "_", item.name)
            expected_items.add(sanitized_name)

        # Verify that key items are in the CREATE TABLE statement
        for item_name in expected_items:
            # Skip PACKET_TIMESECONDS and RECEIVED_TIMESECONDS as they're handled separately
            if item_name in ["PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS"]:
                continue
            self.assertIn(item_name, create_table_sql, f"Expected item '{item_name}' to be in CREATE TABLE statement")

        # Create a JSON data dictionary with values for all items
        json_data = {}
        for item in packet.sorted_items:
            # Use different types to test various data handling
            if "TEMP" in item.name:
                json_data[item.name] = -100.0  # float
            elif "ARY" in item.name or "BLOCK" in item.name:
                json_data[item.name] = [1, 2, 3, 4, 5]  # array/block
            elif "ASCIICMD" in item.name:
                json_data[item.name] = "TEST COMMAND"  # string
            elif "STATUS" in item.name:
                json_data[item.name] = 0  # int
            elif "TIME" in item.name:
                json_data[item.name] = int(time.time())  # timestamp
            else:
                json_data[item.name] = 42  # default int value

        # Add PACKET_TIMESECONDS and RECEIVED_TIMESECONDS
        current_time = time.time()
        json_data["PACKET_TIMESECONDS"] = current_time
        json_data["RECEIVED_TIMESECONDS"] = current_time

        # Write test data to topic
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        # Process the data
        tsdb.read_topics()

        # Verify ingest.row was called
        self.assertTrue(mock_ingest.row.called, "ingest.row should have been called")

        # Get the columns that were written
        call_args = mock_ingest.row.call_args
        columns_written = call_args[1]["columns"]

        # Verify all expected items (except arrays and blocks) are present as columns
        # Arrays and blocks may be serialized differently
        for item_name in expected_items:
            # Skip array items as they may be converted to JSON strings
            if item_name in ["ARY", "ARY2", "BLOCKTEST"]:
                continue
            # PACKET_TIMESECONDS and RECEIVED_TIMESECONDS are added separately
            if item_name in columns_written or f"{item_name}" in str(columns_written):
                # Item is present
                pass
            else:
                # Check if it was written with any value
                self.assertIn(item_name, columns_written, f"Expected item '{item_name}' to be written as a column")

        # Verify at least the key items are present
        key_items = ["TEMP1", "TEMP2", "TEMP3", "TEMP4", "COLLECTS", "PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS"]
        for key_item in key_items:
            self.assertIn(key_item, columns_written, f"Key item '{key_item}' should be present in columns")

        # Verify the table name is correct
        self.assertEqual(call_args[0][0], "INST__HEALTH_STATUS")


if __name__ == "__main__":
    unittest.main()
