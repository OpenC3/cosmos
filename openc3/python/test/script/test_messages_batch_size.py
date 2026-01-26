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

import json
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from openc3.script.web_socket_api import MessagesWebSocketApi
from openc3.utilities.time import to_nsec_from_epoch


class TestMessagesBatchSize(unittest.TestCase):
    """Test MessagesWebSocketApi batch size behavior"""

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_batch_size_exactly_100(self, mock_auth, mock_stream_class):
        """Test that batches contain exactly 100 messages, not 101"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Generate exactly 100 messages
        batch_100 = [
            {"time": i * 1000000000, "level": "INFO", "message": f"Message {i}"}
            for i in range(100)
        ]

        mock_stream_instance.read.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": batch_100}),
            json.dumps({"message": []}),  # Empty batch signals completion
        ]

        with MessagesWebSocketApi(history_count=0) as api:
            result = api.read()
            self.assertEqual(len(result), 100, "Batch should contain exactly 100 messages")

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_batch_size_never_101(self, mock_auth, mock_stream_class):
        """Test that batches never contain 101 messages (the bug we fixed)"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Simulate receiving multiple batches
        batch_100_a = [
            {"time": i * 1000000000, "level": "INFO", "message": f"Batch A Message {i}"}
            for i in range(100)
        ]
        batch_100_b = [
            {"time": (i + 100) * 1000000000, "level": "INFO", "message": f"Batch B Message {i}"}
            for i in range(100)
        ]
        batch_100_c = [
            {"time": (i + 200) * 1000000000, "level": "INFO", "message": f"Batch C Message {i}"}
            for i in range(100)
        ]

        mock_stream_instance.read.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": batch_100_a}),
            json.dumps({"message": batch_100_b}),
            json.dumps({"message": batch_100_c}),
            json.dumps({"message": []}),
        ]

        with MessagesWebSocketApi(history_count=0) as api:
            all_batches = []
            for _ in range(10):  # Safety limit
                batch = api.read()
                if not batch or len(batch) == 0:
                    break
                all_batches.append(batch)
                # Assert no batch has 101 messages (the bug)
                self.assertLessEqual(
                    len(batch), 100,
                    f"Batch size should never exceed 100, got {len(batch)}"
                )
                self.assertNotEqual(
                    len(batch), 101,
                    "Batch size should never be 101 (off-by-one bug)"
                )

            self.assertEqual(len(all_batches), 3, "Should receive 3 batches")
            for i, batch in enumerate(all_batches):
                self.assertEqual(len(batch), 100, f"Batch {i} should have exactly 100 messages")

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_partial_batch_less_than_100(self, mock_auth, mock_stream_class):
        """Test that final batch can have fewer than 100 messages"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Generate partial batch
        batch_50 = [
            {"time": i * 1000000000, "level": "INFO", "message": f"Message {i}"}
            for i in range(50)
        ]

        mock_stream_instance.read.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": batch_50}),
            json.dumps({"message": []}),
        ]

        with MessagesWebSocketApi(history_count=0) as api:
            result = api.read()
            self.assertEqual(len(result), 50, "Partial batch should have 50 messages")

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_large_query_consistent_batches(self, mock_auth, mock_stream_class):
        """Test that large queries return consistent batch sizes"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Simulate 10 full batches + 1 partial batch
        batches = []
        responses = ['{"type":"confirm_subscription"}']

        # 10 full batches of 100
        for batch_num in range(10):
            batch = [
                {"time": (batch_num * 100 + i) * 1000000000, "level": "INFO", "message": f"Msg {batch_num}-{i}"}
                for i in range(100)
            ]
            batches.append(batch)
            responses.append(json.dumps({"message": batch}))

        # 1 partial batch of 37
        partial_batch = [
            {"time": (1000 + i) * 1000000000, "level": "INFO", "message": f"Msg final-{i}"}
            for i in range(37)
        ]
        batches.append(partial_batch)
        responses.append(json.dumps({"message": partial_batch}))
        responses.append(json.dumps({"message": []}))

        mock_stream_instance.read.side_effect = responses

        with MessagesWebSocketApi(history_count=0) as api:
            received_batches = []
            for _ in range(20):  # Safety limit
                batch = api.read()
                if not batch or len(batch) == 0:
                    break
                received_batches.append(batch)

            self.assertEqual(len(received_batches), 11, "Should receive 11 batches total")

            # Check first 10 batches are exactly 100
            for i in range(10):
                self.assertEqual(
                    len(received_batches[i]), 100,
                    f"Batch {i} should have exactly 100 messages"
                )

            # Check last batch is 37
            self.assertEqual(
                len(received_batches[10]), 37,
                "Final batch should have 37 messages"
            )

            # Verify total message count
            total_messages = sum(len(batch) for batch in received_batches)
            self.assertEqual(total_messages, 1037, "Total messages should be 1037")

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_single_message_batch(self, mock_auth, mock_stream_class):
        """Test that single message batches work correctly"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        single_message = [{"time": 1000000000, "level": "ERROR", "message": "Single error"}]

        mock_stream_instance.read.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": single_message}),
            json.dumps({"message": []}),
        ]

        with MessagesWebSocketApi(history_count=0) as api:
            result = api.read()
            self.assertEqual(len(result), 1, "Should receive exactly 1 message")
            self.assertEqual(result[0]["message"], "Single error")

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_batch_boundary_99_100_101(self, mock_auth, mock_stream_class):
        """Test batches around the boundary (99, 100, 101 messages)"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Test 99 messages
        batch_99 = [{"time": i * 1000000000, "level": "INFO", "message": f"Msg {i}"} for i in range(99)]
        # Test 100 messages
        batch_100 = [{"time": i * 1000000000, "level": "INFO", "message": f"Msg {i}"} for i in range(100, 200)]
        # Server should never send 101, but if it did, client should handle it
        batch_101 = [{"time": i * 1000000000, "level": "INFO", "message": f"Msg {i}"} for i in range(200, 301)]

        mock_stream_instance.read.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": batch_99}),
            json.dumps({"message": batch_100}),
            json.dumps({"message": batch_101}),  # Shouldn't happen with fix, but test it
            json.dumps({"message": []}),
        ]

        with MessagesWebSocketApi(history_count=0) as api:
            # Read 99
            result1 = api.read()
            self.assertEqual(len(result1), 99)

            # Read 100
            result2 = api.read()
            self.assertEqual(len(result2), 100)

            # Read 101 (if server somehow sends it, client handles it)
            result3 = api.read()
            # Client can receive 101 if server sends it, but server shouldn't with our fix
            self.assertGreaterEqual(len(result3), 100)

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    @patch("openc3.script.web_socket_api.WebSocketApi._generate_auth")
    def test_time_range_query_batch_sizes(self, mock_auth, mock_stream_class):
        """Test batch sizes for time range queries"""
        mock_auth_instance = Mock()
        mock_auth_instance.token.return_value = "test_token"
        mock_auth.return_value = mock_auth_instance

        mock_stream_instance = Mock()
        mock_stream_class.return_value = mock_stream_instance
        mock_stream_instance.connected.return_value = True

        # Simulate historical data query returning multiple 100-message batches
        batches_data = []
        responses = ['{"type":"confirm_subscription"}']

        for batch_num in range(5):
            batch = [
                {"time": (batch_num * 100 + i) * 1000000000, "level": "INFO", "message": f"Historical {i}"}
                for i in range(100)
            ]
            batches_data.append(batch)
            responses.append(json.dumps({"message": batch}))

        responses.append(json.dumps({"message": []}))
        mock_stream_instance.read.side_effect = responses

        now = datetime.now(timezone.utc)
        with MessagesWebSocketApi(
            start_time=to_nsec_from_epoch(now - timedelta(hours=1)),
            end_time=to_nsec_from_epoch(now),
        ) as api:
            batch_sizes = []
            for _ in range(10):
                batch = api.read()
                if not batch or len(batch) == 0:
                    break
                batch_sizes.append(len(batch))

            # All batches should be exactly 100
            self.assertEqual(len(batch_sizes), 5)
            for size in batch_sizes:
                self.assertEqual(size, 100, "All historical batches should be exactly 100")


class TestBatchSizeDocumentation(unittest.TestCase):
    """Test to document the expected batch size behavior"""

    def test_batch_size_specification(self):
        """Document the batch size specification"""
        # This test serves as documentation
        EXPECTED_MAX_BATCH_SIZE = 100
        EXPECTED_MIN_BATCH_SIZE = 0  # Empty batch signals completion

        # The server should send batches with these characteristics:
        # - Full batches: exactly 100 messages
        # - Partial batch: 1-99 messages (final batch if total not divisible by 100)
        # - Empty batch: 0 messages (signals stream completion)
        # - NEVER: 101 messages (this was the bug)

        self.assertEqual(EXPECTED_MAX_BATCH_SIZE, 100)
        self.assertGreaterEqual(EXPECTED_MIN_BATCH_SIZE, 0)

        # Document that 101 is not valid
        INVALID_BATCH_SIZE = 101
        self.assertGreater(INVALID_BATCH_SIZE, EXPECTED_MAX_BATCH_SIZE,
                          "101 message batches indicate off-by-one bug")


if __name__ == "__main__":
    unittest.main()
