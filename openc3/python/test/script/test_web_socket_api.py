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

import time
import unittest
from unittest.mock import Mock, patch

from openc3.script.web_socket_api import WebSocketApi


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
