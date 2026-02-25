# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import base64
import json
import os
import re
import time
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch

from questdb.ingress import IngressError

from openc3.microservices.tsdb_microservice import TsdbMicroservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.target_model import TargetModel
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.topics.topic import Topic
from openc3.utilities.questdb_client import (
    FLOAT64_NAN_SENTINEL,
    FLOAT64_POS_INF_SENTINEL,
)
from test.test_helper import System, capture_io, mock_redis, setup_system


class TestTsdbMicroservice(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        setup_system()

        # Prevent microservice status thread from leaking between tests
        patcher = patch("openc3.microservices.microservice.Microservice._status_thread")
        patcher.start()
        self.addCleanup(patcher.stop)

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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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
        self.assertIsNotNone(tsdb.questdb.ingest)
        self.assertIsNotNone(tsdb.questdb.query)
        mock_ingest.establish.assert_called_once()

        # Verify table creation was attempted
        mock_cursor.execute.assert_called()

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        self.assertIn("Failed to connect to QuestDB", str(context.exception))

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        self.assertIn("Failed to connect to QuestDB", str(context.exception))

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Check that table was created with correct name (TLM__ prefix for telemetry)
        calls = mock_cursor.execute.call_args_list
        self.assertTrue(any("DEFAULT__TLM__INST__HEALTH_STATUS" in str(call) for call in calls))

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        # Mock get_tlm to return a dummy packet dict
        mock_get_tlm.return_value = {"items": []}

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{INST}__TEST?PKT:1"],
            target_names=["INST"],
        )
        model.create()

        for stdout in capture_io():
            TsdbMicroservice("DEFAULT__TSDB__TEST")
            # Should warn about invalid characters
            self.assertIn("changed to", stdout.getvalue())

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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
        # The designated timestamp columns are now named PACKET_TIMESECONDS and RECEIVED_TIMESECONDS
        self.assertIn("PACKET_TIMESECONDS timestamp_ns", create_table_sql)
        self.assertIn("RECEIVED_TIMESECONDS timestamp_ns", create_table_sql)
        # PACKET_TIMEFORMATTED and RECEIVED_TIMEFORMATTED are derived from the timestamp columns
        # and should NOT be stored as separate columns
        self.assertNotIn("PACKET_TIMEFORMATTED", create_table_sql)
        self.assertNotIn("RECEIVED_TIMEFORMATTED", create_table_sql)
        self.assertIn('"CCSDSTYPE" int', create_table_sql)
        # TIMESEC is 32 bits so upgraded to long
        self.assertIn('"TIMESEC" long', create_table_sql)
        # Arrays are now stored as varchar (JSON serialized) to avoid QuestDB array type issues
        self.assertIn('"ARY" varchar', create_table_sql)
        # Block of 80 bits becomes encoded varchar
        self.assertIn('"BLOCKTEST" varchar', create_table_sql)
        self.assertIn('"BRACKET[0]" int', create_table_sql)
        # Even a single bit is an int column
        self.assertIn('"1BIT" int', create_table_sql)
        # 63 bits is a long
        self.assertIn('"63BITS" long', create_table_sql)
        # 64 bits uses DECIMAL(20, 0) for full 64-bit integer support
        self.assertIn('"64BITS" DECIMAL(20, 0)', create_table_sql)
        # DERIVED items are now created as VARCHAR to avoid type conflicts
        self.assertIn('"DERIVED_GENERIC" varchar', create_table_sql)

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
            self.assertIn(
                item_name,
                create_table_sql,
                f"Expected item '{item_name}' to be in CREATE TABLE statement",
            )

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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
        self.assertEqual(call_args[0][0], "DEFAULT__TLM__INST__HEALTH_STATUS")
        self.assertIn("TEMP1", call_args[1]["columns"])
        self.assertEqual(call_args[1]["columns"]["TEMP1"], 42)

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_large_integers(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics passes through large integers unchanged (QuestDB handles overflow)"""
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

        # Values outside signed 64-bit range are converted to strings
        # (create_table defines 64-bit columns as VARCHAR to handle this)
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        self.assertEqual(call_args[1]["columns"]["BIGVAL"], str(2**64))
        self.assertEqual(call_args[1]["columns"]["SMALLVAL"], str(-(2**64)))

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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
        # NaN and Infinity are encoded as sentinel values because QuestDB stores them as NULL
        self.assertEqual(call_args[1]["columns"]["TEMP2"], FLOAT64_NAN_SENTINEL)
        self.assertEqual(call_args[1]["columns"]["TEMP3"], FLOAT64_POS_INF_SENTINEL)

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_numeric_arrays(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics serializes numeric arrays as JSON strings for storage"""
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

        # Arrays are now always JSON serialized to avoid QuestDB array type issues
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        result = call_args[1]["columns"]["ARRAY"]
        # Arrays are JSON serialized as strings
        self.assertIsInstance(result, str)
        self.assertEqual(result, "[1.0, 2.0, 3.0, 4.0]")

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_timestamp_columns(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics stores received time in RECEIVED_TIMESECONDS and skips TIMEFORMATTED columns"""
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
        received_time = current_time + 1
        json_data = {
            "PACKET_TIMESECONDS": current_time,
            "RECEIVED_TIMESECONDS": received_time,
            "PACKET_TIMEFORMATTED": "2026/01/23 00:00:00.000",
            "RECEIVED_TIMEFORMATTED": "2026/01/23 00:00:01.000",
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

        # Verify row was written
        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        columns = call_args[1]["columns"]

        # Time items from json_data should NOT be stored as regular columns
        # PACKET_TIMESECONDS and RECEIVED_TIMESECONDS come from message metadata (time, received_time)
        # PACKET_TIMEFORMATTED and RECEIVED_TIMEFORMATTED are calculated on read
        self.assertNotIn("PACKET_TIMESECONDS", columns)
        self.assertNotIn("RECEIVED_TIMESECONDS", columns)
        self.assertNotIn("PACKET_TIMEFORMATTED", columns)
        self.assertNotIn("RECEIVED_TIMEFORMATTED", columns)

        # RECEIVED_TIMESECONDS column is set from message's received_time field (not json_data)
        # The test message doesn't include received_time in msg_hash, so it won't be present
        # unless we explicitly add it to the test

        # Other data should still be present
        self.assertEqual(columns["TEMP1"], 100)

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_cast_error(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles type cast errors by casting value"""
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
            "error in line 1: table: DEFAULT__TLM__INST__HEALTH_STATUS, column: TEMP1; "
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
            # Should have logged warning about casting the value
            self.assertIn("expected LONG but received FLOAT", stdout.getvalue())

        # Should have called row twice (failed, then succeeded after cast)
        self.assertEqual(mock_ingest.row.call_count, 2)

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_array_to_scalar_cast_error(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles array-to-scalar cast errors by registering for JSON serialization"""
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

        # Setup mock to raise IngressError for array-to-scalar conversion on first call,
        # then succeed on retry after JSON serialization
        error_msg = (
            "error in line 1: table: DEFAULT__TLM__INST__HEALTH_STATUS, column: JSON_ITEM; "
            'cast error from protocol type: DOUBLE[] to column type: INT","line":1'
        )
        # First call fails (triggers JSON serialization), second call (retry) succeeds
        mock_ingest.row.side_effect = [IngressError(1, error_msg), None]
        mock_ingest.flush.side_effect = IngressError(1, error_msg)

        # Write test data with array
        json_data = {"JSON_ITEM": [1.0, 2.0, 3.0]}
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
            # Should have logged warning about array-to-scalar conversion and retry
            self.assertIn("Serializing as JSON string", stdout.getvalue())

        # Column should be registered for JSON serialization
        self.assertIn("DEFAULT__TLM__INST__HEALTH_STATUS__JSON_ITEM", tsdb.questdb.json_columns)

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_handles_array_to_varchar_cast_error(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics handles ARRAY (no brackets) to VARCHAR cast errors"""
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

        # Setup mock to raise IngressError for ARRAY (no brackets) to VARCHAR conversion
        # This matches the error format from QuestDB when sending array to varchar column
        error_msg = (
            "error in line 1: table: DEFAULT__TLM__INST__HEALTH_STATUS, column: ITEM7; "
            'cast error from protocol type: ARRAY to column type: VARCHAR","line":1'
        )
        # First call fails (triggers JSON serialization), second call (retry) succeeds
        mock_ingest.row.side_effect = [IngressError(1, error_msg), None]
        mock_ingest.flush.side_effect = IngressError(1, error_msg)

        # Write test data with numeric array (will be converted to numpy array, triggering ARRAY type)
        json_data = {"ITEM7": [1.0, 2.0, 3.0]}
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
            # Should have logged warning about array-to-scalar conversion and retry
            self.assertIn("Serializing as JSON string", stdout.getvalue())

        # Column should be registered for JSON serialization
        self.assertIn("DEFAULT__TLM__INST__HEALTH_STATUS__ITEM7", tsdb.questdb.json_columns)

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_variable_length_array(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that variable-length arrays (array_size=0) create varchar columns (JSON serialized)"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Mock packet with variable-length array (array_size=0)
        mock_get_tlm.return_value = {
            "items": [
                {
                    "name": "VAR_ARRAY",
                    "data_type": "UINT",
                    "bit_size": 8,
                    "array_size": 0,
                },
            ]
        }

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{TEST}__PACKET"],
            target_names=["TEST"],
        )
        model.create()

        TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify CREATE TABLE was called
        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0, "CREATE TABLE should have been called")

        # Arrays are now stored as varchar (JSON serialized) to avoid QuestDB array type issues
        create_table_sql = str(create_table_calls[0])
        self.assertIn('"VAR_ARRAY" varchar', create_table_sql)

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_non_numeric_array(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that non-numeric arrays (data_type=ARRAY) create VARCHAR columns with JSON serialization"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Mock packet with non-numeric array (data_type="ARRAY")
        mock_get_tlm.return_value = {
            "items": [
                {
                    "name": "MIXED_ARRAY",
                    "data_type": "ARRAY",
                    "bit_size": 8,
                    "array_size": 0,
                },
                {
                    "name": "STRING_ARRAY",
                    "data_type": "STRING",
                    "bit_size": 64,
                    "array_size": 10,
                },
            ]
        }

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{TEST}__PACKET"],
            target_names=["TEST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify CREATE TABLE was called
        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0, "CREATE TABLE should have been called")

        # Non-numeric arrays should use VARCHAR type
        create_table_sql = str(create_table_calls[0])
        self.assertIn('"MIXED_ARRAY" varchar', create_table_sql)
        self.assertIn('"STRING_ARRAY" varchar', create_table_sql)

        # Non-numeric arrays should be registered for JSON serialization
        self.assertIn("DEFAULT__TLM__TEST__PACKET__MIXED_ARRAY", tsdb.questdb.json_columns)
        self.assertIn("DEFAULT__TLM__TEST__PACKET__STRING_ARRAY", tsdb.questdb.json_columns)

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_derived_with_typed_conversion(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that DERIVED items with declared converted_type use that type instead of VARCHAR"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Mock packet with DERIVED items that have typed conversions
        mock_get_tlm.return_value = {
            "items": [
                # DERIVED with FLOAT 32 conversion (e.g., TEMP1_MICRO)
                {
                    "name": "DERIVED_FLOAT32",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "FLOAT",
                        "converted_bit_size": 32,
                    },
                },
                # DERIVED with FLOAT 64 conversion
                {
                    "name": "DERIVED_FLOAT64",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "FLOAT",
                        "converted_bit_size": 64,
                    },
                },
                # DERIVED with INT 16 conversion
                {
                    "name": "DERIVED_INT16",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "INT",
                        "converted_bit_size": 16,
                    },
                },
                # DERIVED with UINT 32 conversion
                {
                    "name": "DERIVED_UINT32",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "UINT",
                        "converted_bit_size": 32,
                    },
                },
                # DERIVED with INT 64 conversion
                {
                    "name": "DERIVED_INT64",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "INT",
                        "converted_bit_size": 64,
                    },
                },
                # DERIVED with STRING conversion
                {
                    "name": "DERIVED_STRING",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "STRING",
                        "converted_bit_size": 0,
                    },
                },
                # DERIVED with TIME conversion (e.g., PACKET_TIME from unix_time_conversion)
                {
                    "name": "DERIVED_TIME",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "TIME",
                        "converted_bit_size": 0,
                    },
                },
                # DERIVED with no conversion (should be VARCHAR/JSON)
                {"name": "DERIVED_NO_CONV", "data_type": "DERIVED"},
                # DERIVED with conversion but no converted_type (should be VARCHAR/JSON)
                {
                    "name": "DERIVED_NIL_TYPE",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": None,
                        "converted_bit_size": 0,
                    },
                },
                # DERIVED with ARRAY type (should be VARCHAR/JSON)
                {
                    "name": "DERIVED_ARRAY",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "ARRAY",
                        "converted_bit_size": 0,
                    },
                },
                # DERIVED with OBJECT type (should be VARCHAR/JSON)
                {
                    "name": "DERIVED_OBJECT",
                    "data_type": "DERIVED",
                    "read_conversion": {
                        "converted_type": "OBJECT",
                        "converted_bit_size": 0,
                    },
                },
            ]
        }

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{TEST}__PACKET"],
            target_names=["TEST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify CREATE TABLE was called
        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0, "CREATE TABLE should have been called")

        create_table_sql = str(create_table_calls[0])

        # DERIVED items with typed conversions should use native QuestDB types
        self.assertIn('"DERIVED_FLOAT32" float', create_table_sql)
        self.assertIn('"DERIVED_FLOAT64" double', create_table_sql)
        self.assertIn('"DERIVED_INT16" int', create_table_sql)
        self.assertIn('"DERIVED_UINT32" long', create_table_sql)
        # 64-bit integers use DECIMAL(20, 0) for full range support
        self.assertIn('"DERIVED_INT64" DECIMAL(20, 0)', create_table_sql)
        self.assertIn('"DERIVED_STRING" varchar', create_table_sql)
        self.assertIn('"DERIVED_TIME" varchar', create_table_sql)

        # DERIVED items without type info or with complex types should use VARCHAR
        self.assertIn('"DERIVED_NO_CONV" varchar', create_table_sql)
        self.assertIn('"DERIVED_NIL_TYPE" varchar', create_table_sql)
        self.assertIn('"DERIVED_ARRAY" varchar', create_table_sql)
        self.assertIn('"DERIVED_OBJECT" varchar', create_table_sql)

        # Only untyped/complex DERIVED items should be registered for JSON serialization
        self.assertIn("DEFAULT__TLM__TEST__PACKET__DERIVED_NO_CONV", tsdb.questdb.json_columns)
        self.assertIn("DEFAULT__TLM__TEST__PACKET__DERIVED_NIL_TYPE", tsdb.questdb.json_columns)
        self.assertIn("DEFAULT__TLM__TEST__PACKET__DERIVED_ARRAY", tsdb.questdb.json_columns)
        self.assertIn("DEFAULT__TLM__TEST__PACKET__DERIVED_OBJECT", tsdb.questdb.json_columns)

        # Typed DERIVED items should NOT be registered for JSON serialization
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_FLOAT32", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_FLOAT64", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_INT16", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_UINT32", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_INT64", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_STRING", tsdb.questdb.json_columns)
        self.assertNotIn("DEFAULT__TLM__TEST__PACKET__DERIVED_TIME", tsdb.questdb.json_columns)

        # Float columns should be registered with correct bit sizes
        self.assertEqual(tsdb.questdb.float_bit_sizes.get("DEFAULT__TLM__TEST__PACKET__DERIVED_FLOAT32"), 32)
        self.assertEqual(tsdb.questdb.float_bit_sizes.get("DEFAULT__TLM__TEST__PACKET__DERIVED_FLOAT64"), 64)

        # 64-bit integer columns should be registered for DECIMAL conversion
        self.assertIn("DEFAULT__TLM__TEST__PACKET__DERIVED_INT64", tsdb.questdb.decimal_int_columns)

    def test_convert_value_arrays_json_serialized(self):
        """Test that all arrays are JSON serialized to avoid QuestDB type conflicts"""
        from openc3.utilities.questdb_client import QuestDBClient

        client = QuestDBClient()

        # Mixed array with string element should be JSON serialized
        value, skip = client.convert_value([1, "mixed", 3.14], "ITEM", None)
        self.assertFalse(skip)
        self.assertEqual(value, '[1, "mixed", 3.14]')

        # Array with all strings should be JSON serialized
        value, skip = client.convert_value(["a", "b", "c"], "ITEM", None)
        self.assertFalse(skip)
        self.assertEqual(value, '["a", "b", "c"]')

        # Empty array should be JSON serialized
        value, skip = client.convert_value([], "ITEM", None)
        self.assertFalse(skip)
        self.assertEqual(value, "[]")

        # Pure numeric arrays are also JSON serialized to avoid QuestDB array type issues
        value, skip = client.convert_value([1.0, 2.0, 3.0], "ITEM", None)
        self.assertFalse(skip)
        self.assertEqual(value, "[1.0, 2.0, 3.0]")

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        # Note: With the refactored code, IngressError is handled gracefully by handle_ingress_error()
        # and doesn't set self.error. Only unhandled exceptions in run() set self.error.

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
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

        TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Verify table creation was not attempted for UNKNOWN
        calls = mock_cursor.execute.call_args_list
        self.assertFalse(any("UNKNOWN" in str(call) for call in calls))

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_stores_all_packet_items(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that all items from a packet are stored as columns in the table"""
        # Create a mock packet dict with items
        items = [
            {"name": "TEMP1", "data_type": "FLOAT", "bit_size": 32},
            {"name": "TEMP2", "data_type": "FLOAT", "bit_size": 32},
            {"name": "TEMP3", "data_type": "FLOAT", "bit_size": 32},
            {"name": "TEMP4", "data_type": "FLOAT", "bit_size": 32},
            {"name": "COLLECTS", "data_type": "UINT", "bit_size": 16},
            {"name": "ASCIICMD", "data_type": "STRING", "bit_size": 2048},
            {"name": "ARY", "data_type": "BLOCK", "bit_size": 80, "array_size": 80},
            {"name": "GROUND1STATUS", "data_type": "UINT", "bit_size": 8},
            {"name": "BLOCKTEST", "data_type": "BLOCK", "bit_size": 80},
        ]
        packet = {"items": items}

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
        for item in items:
            # Sanitize item name the same way tsdb_microservice does
            sanitized_name = re.sub(r'[?\.,\'"\\/:)(+\-*%~;]', "_", item["name"])
            expected_items.add(sanitized_name)

        # Verify that key items are in the CREATE TABLE statement
        for item_name in expected_items:
            # Skip PACKET_TIMESECONDS and RECEIVED_TIMESECONDS as they're handled separately
            if item_name in ["PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS"]:
                continue
            self.assertIn(
                item_name,
                create_table_sql,
                f"Expected item '{item_name}' to be in CREATE TABLE statement",
            )

        # Create a JSON data dictionary with values for all items
        json_data = {}
        for item in items:
            # Use different types to test various data handling
            if "TEMP" in item["name"]:
                json_data[item["name"]] = -100.0  # float
            elif "ARY" in item["name"] or "BLOCK" in item["name"]:
                json_data[item["name"]] = [1, 2, 3, 4, 5]  # array/block
            elif "ASCIICMD" in item["name"]:
                json_data[item["name"]] = "TEST COMMAND"  # string
            elif "STATUS" in item["name"]:
                json_data[item["name"]] = 0  # int
            elif "TIME" in item["name"]:
                json_data[item["name"]] = int(time.time())  # timestamp
            else:
                json_data[item["name"]] = 42  # default int value

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
                self.assertIn(
                    item_name,
                    columns_written,
                    f"Expected item '{item_name}' to be written as a column",
                )

        # Verify at least the key items are present
        # Note: PACKET_TIMESECONDS and RECEIVED_TIMESECONDS are stored as timestamp_ns columns
        # but the values come from the topic message metadata (time, received_time), not json_data
        key_items = ["TEMP1", "TEMP2", "TEMP3", "TEMP4", "COLLECTS"]
        for key_item in key_items:
            self.assertIn(
                key_item,
                columns_written,
                f"Key item '{key_item}' should be present in columns",
            )

        # Verify the table name is correct (TLM__ prefix for telemetry)
        self.assertEqual(call_args[0][0], "DEFAULT__TLM__INST__HEALTH_STATUS")

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_sets_cosmos_extra(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics sets COSMOS_EXTRA when extra field is present"""
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

        # Write test data with extra field
        json_data = {"TEMP1": 42}
        extra_data = {"vcid": 1, "data_source": "replay"}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"stored": b"false",
                b"extra": json.dumps(extra_data).encode(),
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        columns = call_args[1]["columns"]
        self.assertIn("COSMOS_EXTRA", columns)
        self.assertEqual(columns["COSMOS_EXTRA"], json.dumps(extra_data))

    def test_canonical_type_normalizes_case_and_whitespace(self):
        """Test _canonical_type uppercases and strips whitespace for consistent comparison"""
        from openc3.utilities.questdb_client import QuestDBClient

        # Lowercase to uppercase
        self.assertEqual(QuestDBClient._canonical_type("float"), "FLOAT")
        self.assertEqual(QuestDBClient._canonical_type("double"), "DOUBLE")
        self.assertEqual(QuestDBClient._canonical_type("int"), "INT")
        self.assertEqual(QuestDBClient._canonical_type("long"), "LONG")
        self.assertEqual(QuestDBClient._canonical_type("varchar"), "VARCHAR")
        self.assertEqual(QuestDBClient._canonical_type("SYMBOL"), "SYMBOL")
        self.assertEqual(QuestDBClient._canonical_type("timestamp_ns"), "TIMESTAMP_NS")

        # DECIMAL with different whitespace normalizes to the same string
        self.assertEqual(QuestDBClient._canonical_type("DECIMAL(20, 0)"), "DECIMAL(20,0)")
        self.assertEqual(QuestDBClient._canonical_type("DECIMAL(20,0)"), "DECIMAL(20,0)")

        # Different DECIMAL parameters remain distinct
        self.assertNotEqual(
            QuestDBClient._canonical_type("DECIMAL(20, 0)"),
            QuestDBClient._canonical_type("DECIMAL(22, 0)"),
        )

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_create_table_conversion_without_converted_type_uses_json(
        self, mock_system, mock_psycopg, mock_sender, mock_get_tlm
    ):
        """Test that a read_conversion with no converted_type creates a varchar __C column registered for JSON"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Simulates a user-defined Python conversion (like twos_comp_conversion.py)
        # that does not declare converted_type
        mock_get_tlm.return_value = {
            "items": [
                {
                    "name": "ANGLE",
                    "data_type": "INT",
                    "bit_size": 16,
                    "read_conversion": {
                        "converted_type": None,
                        "converted_bit_size": 0,
                    },
                },
            ]
        }

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{TEST}__PKT"],
            target_names=["TEST"],
        )
        model.create()

        tsdb = TsdbMicroservice("DEFAULT__TSDB__TEST")

        create_table_calls = [call for call in mock_cursor.execute.call_args_list if "CREATE TABLE" in str(call)]
        self.assertTrue(len(create_table_calls) > 0)
        create_table_sql = str(create_table_calls[0])

        # Raw column should be int, converted column should be varchar
        self.assertIn('"ANGLE" int', create_table_sql)
        self.assertIn('"ANGLE__C" varchar', create_table_sql)

        # The __C column should be registered for JSON serialization so integer values get stringified
        self.assertIn("DEFAULT__TLM__TEST__PKT__ANGLE__C", tsdb.questdb.json_columns)

    @patch("openc3.microservices.tsdb_microservice.get_tlm")
    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_reconcile_skips_alter_when_decimal_types_match(self, mock_system, mock_psycopg, mock_sender, mock_get_tlm):
        """Test that reconciliation does not ALTER when existing DECIMAL(20,0) matches desired DECIMAL(20, 0)"""
        mock_query = Mock()
        mock_psycopg.return_value = mock_query
        mock_cursor = Mock()
        mock_query.cursor.return_value.__enter__ = Mock(return_value=mock_cursor)
        mock_query.cursor.return_value.__exit__ = Mock(return_value=False)

        # Simulate an existing table with DECIMAL(20,0) (no space, as QuestDB returns)
        mock_cursor.fetchall.return_value = [
            ("PACKET_TIMESECONDS", "TIMESTAMP_NS"),
            ("RECEIVED_TIMESECONDS", "TIMESTAMP_NS"),
            ("RECEIVED_COUNT", "LONG"),
            ("COSMOS_DATA_TAG", "SYMBOL"),
            ("BIGVAL", "DECIMAL(20,0)"),
        ]

        mock_get_tlm.return_value = {
            "items": [
                {
                    "name": "BIGVAL",
                    "data_type": "UINT",
                    "bit_size": 64,
                },
            ]
        }

        model = MicroserviceModel(
            "DEFAULT__TSDB__TEST",
            scope="DEFAULT",
            topics=["DEFAULT__DECOM__{TEST}__PKT"],
            target_names=["TEST"],
        )
        model.create()

        TsdbMicroservice("DEFAULT__TSDB__TEST")

        # Should NOT have issued any ALTER COLUMN TYPE statements
        alter_calls = [
            call for call in mock_cursor.execute.call_args_list if "ALTER" in str(call) and "TYPE" in str(call)
        ]
        self.assertEqual(len(alter_calls), 0, f"Should not ALTER matching DECIMAL types, but got: {alter_calls}")

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_handle_ingress_error_persists_varchar_tracking(self, mock_system, mock_psycopg, mock_sender):
        """Test that handle_ingress_error registers VARCHAR columns so future rows don't re-error"""
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

        # Simulate INTEGER to VARCHAR cast error (the reported user issue)
        error_msg = (
            "error in line 1: table: TLM__INST__HEALTH_STATUS, column: ITEM__C; "
            'cast error from protocol type: INTEGER to column type: VARCHAR","line":1'
        )
        mock_ingest.row.side_effect = [IngressError(1, error_msg), None]

        json_data = {"ITEM__C": 42}
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
            self.assertIn("expected VARCHAR but received INTEGER", stdout.getvalue())

        # The column should now be tracked in varchar_columns so convert_value() will str() it
        self.assertIn("TLM__INST__HEALTH_STATUS__ITEM__C", tsdb.questdb.varchar_columns)

        # Verify retry was called with the value cast to string
        retry_call = mock_ingest.row.call_args_list[1]
        self.assertEqual(retry_call[1]["columns"]["ITEM__C"], "42")

    @patch("openc3.utilities.questdb_client.Sender")
    @patch("openc3.utilities.questdb_client.psycopg.connect")
    @patch("openc3.microservices.microservice.System")
    def test_read_topics_omits_cosmos_extra_when_missing(self, mock_system, mock_psycopg, mock_sender):
        """Test read_topics does not set COSMOS_EXTRA when extra field is absent"""
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

        # Write test data without extra field
        json_data = {"TEMP1": 42}
        Topic.write_topic(
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS",
            {
                b"target_name": b"INST",
                b"packet_name": b"HEALTH_STATUS",
                b"time": str(int(time.time() * 1_000_000_000)).encode(),
                b"stored": b"false",
                b"json_data": json.dumps(json_data).encode(),
            },
            "*",
            100,
        )

        tsdb.read_topics()

        mock_ingest.row.assert_called_once()
        call_args = mock_ingest.row.call_args
        columns = call_args[1]["columns"]
        self.assertNotIn("COSMOS_EXTRA", columns)


if __name__ == "__main__":
    unittest.main()
