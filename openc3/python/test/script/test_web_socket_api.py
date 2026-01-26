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
import time
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from websockets.exceptions import ConnectionClosedOK

from openc3.script.web_socket_api import (
    MessagesWebSocketApi,
    WebSocketApi,
)
from openc3.utilities.time import to_nsec_from_epoch


class TestMessagesWebSocketApiConnectionClosed(unittest.TestCase):
    """Test MessagesWebSocketApi connection closed scenarios"""

    def test_connection_closed_ok_returns_none(self):
        """Test that ConnectionClosedOK exception is handled and returns None"""
        from openc3.streams.web_socket_client_stream import WebSocketClientStream

        api = MessagesWebSocketApi(
            start_time=to_nsec_from_epoch(datetime.now(timezone.utc) - timedelta(minutes=5)),
            end_time=to_nsec_from_epoch(datetime.now(timezone.utc)),
        )

        # Create a mock connection that raises ConnectionClosedOK
        mock_connection = Mock()
        messages = [{"time": 1000000000, "level": "INFO", "message": "Final message"}]
        mock_connection.recv.side_effect = [
            '{"type":"confirm_subscription"}',
            json.dumps({"message": messages}),
            ConnectionClosedOK(None, None),  # This should be caught and converted to None
        ]

        # Create a real WebSocketClientStream and replace its connection
        api.stream = WebSocketClientStream(
            url="ws://test.com",
            write_timeout=10.0,
            read_timeout=10.0,
            connect_timeout=5.0,
        )
        api.stream.connection = mock_connection

        # Read the data
        result1 = api.read()
        self.assertEqual(result1, messages)

        # Next read should return None (connection closed gracefully)
        result2 = api.read()
        self.assertIsNone(result2)

        # Verify that ConnectionClosedOK was actually raised (and caught)
        # by checking that recv was called 3 times
        self.assertEqual(mock_connection.recv.call_count, 3)


class TestWebSocketApiEdgeCases(unittest.TestCase):
    """Test edge cases and error conditions"""

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_read_with_timeout(self, mock_stream_class):
        """Test read with timeout parameter"""
        api = WebSocketApi(
            url="ws://test.com/cable",
            authentication=Mock(),
        )
        api.identifier = {"channel": "TestChannel"}
        api.stream = Mock()

        # Simulate slow responses - return multiple ping messages
        call_count = [0]
        def slow_read():
            call_count[0] += 1
            time.sleep(0.15)
            return '{"type":"ping"}'

        api.stream.read.side_effect = slow_read

        # This should timeout after ~0.3 seconds (2 pings at 0.15s each)
        start = time.time()
        with self.assertRaises(TimeoutError):
            api.read(timeout=0.25)
        elapsed = time.time() - start
        # Should have timed out after at least 0.25 seconds
        self.assertGreaterEqual(elapsed, 0.25)
        # Should not take too long (safety check)
        self.assertLess(elapsed, 1.0)
        # Should have called read at least twice
        self.assertGreaterEqual(call_count[0], 2)


if __name__ == "__main__":
    unittest.main()
