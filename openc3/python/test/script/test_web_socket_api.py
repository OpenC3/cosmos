# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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
    RunningScriptWebSocketApi,
    WebSocketApi,
)
from openc3.utilities.time import to_nsec_from_epoch


class TestMessagesWebSocketApiConnectionClosed(unittest.TestCase):
    """Test MessagesWebSocketApi connection closed scenarios"""

    def test_connection_closed_ok_returns_none(self):
        """Test that ConnectionClosedOK exception is handled and returns None"""
        from openc3.streams.web_socket_client_stream import WebSocketClientStream

        mock_auth = Mock()
        mock_auth.token.return_value = "test-token"
        api = MessagesWebSocketApi(
            start_time=to_nsec_from_epoch(datetime.now(timezone.utc) - timedelta(minutes=5)),
            end_time=to_nsec_from_epoch(datetime.now(timezone.utc)),
            authentication=mock_auth,
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
        mock_auth = Mock()
        mock_auth.token.return_value = "test-token"
        api = WebSocketApi(
            url="ws://test.com/cable",
            authentication=mock_auth,
        )
        api.identifier = {"channel": "TestChannel"}
        api.stream = Mock()
        # Skip the subscribe handshake; this test exercises read() timeout during
        # the data phase, not subscription confirmation.
        api.subscribed = True

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


class TestWebSocketApiSubscribe(unittest.TestCase):
    """Verify the subscribe wire format the server is actually expecting."""

    def _make_api(self):
        mock_auth = Mock()
        mock_auth.token.return_value = "test_token"
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth)
        api.identifier = {"channel": "TestChannel"}
        api.stream = Mock()
        # subscribe() now blocks until the server confirms the subscription
        api.stream.read.return_value = '{"type":"confirm_subscription"}'
        return api

    # ActionCable derives `params` (which the server uses for
    # authenticate_subscription!) from the channel identifier JSON, NOT from
    # the `data` field. Putting the token in `data` silently broke every CLI
    # subscription — see commit 8cabbb341.
    def test_token_goes_in_identifier_not_data(self):
        api = self._make_api()
        api.subscribe()

        api.stream.write.assert_called_once()
        outer = json.loads(api.stream.write.call_args[0][0])
        self.assertEqual(outer["command"], "subscribe")
        self.assertNotIn("data", outer)
        identifier = json.loads(outer["identifier"])
        self.assertEqual(identifier["channel"], "TestChannel")
        self.assertEqual(identifier["token"], "test_token")

    def test_subscribe_is_idempotent(self):
        api = self._make_api()
        api.subscribe()
        api.subscribe()
        self.assertEqual(api.stream.write.call_count, 1)

    # Regression: write_action must subscribe (which injects the token into the
    # identifier) BEFORE serializing the identifier, so the message command's
    # identifier matches the subscription's. Otherwise ActionCable silently
    # ignores the action and no data ever streams.
    def test_action_identifier_includes_token(self):
        api = self._make_api()
        api.write_action({"action": "add"})
        frames = [json.loads(c.args[0]) for c in api.stream.write.call_args_list]
        message = next(f for f in frames if f["command"] == "message")
        identifier = json.loads(message["identifier"])
        self.assertEqual(identifier["token"], "test_token")


class TestRunningScriptWebSocketApiTail(unittest.TestCase):
    """Verify the tail protocol: live script events only flow once the client
    performs the 'tail' channel action (see RunningScriptChannel#tail).
    subscribe() blocks until confirm_subscription, so sending 'tail'
    immediately after guarantees the gateway has registered the stream and
    the arm cannot race a broadcast."""

    def _make_api(self):
        mock_auth = Mock()
        mock_auth.token.return_value = "test_token"
        api = RunningScriptWebSocketApi(
            id="spec-script-1",
            url="ws://test.com/script-api/cable",
            authentication=mock_auth,
        )
        api.stream = Mock()
        api.stream.read.return_value = '{"type":"confirm_subscription"}'
        return api

    def _frames(self, api):
        return [json.loads(c.args[0]) for c in api.stream.write.call_args_list]

    def test_subscribe_arms_tail_exactly_once_after_confirmation(self):
        api = self._make_api()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message"])
        self.assertEqual(json.loads(frames[-1]["data"]), {"action": "tail"})

    def test_tail_action_identifier_matches_subscription(self):
        api = self._make_api()
        api.subscribe()
        frames = self._frames(api)
        # Must match exactly: ActionCable routes 'message' commands to a
        # subscription by comparing the raw identifier string
        self.assertEqual(frames[-1]["identifier"], frames[0]["identifier"])
        identifier = json.loads(frames[-1]["identifier"])
        self.assertEqual(identifier["channel"], "RunningScriptChannel")
        self.assertEqual(identifier["id"], "spec-script-1")
        self.assertEqual(identifier["token"], "test_token")

    def test_no_tail_resend_on_subsequent_subscribes(self):
        api = self._make_api()
        api.subscribe()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message"])

    # write_action calls subscribe() internally, which on the first call is
    # the overridden subscribe that itself calls write_action for tail. Prove
    # this does not recurse or duplicate frames and preserves ordering.
    def test_action_triggering_first_subscribe_orders_subscribe_tail_action(self):
        api = self._make_api()
        api.write_action({"action": "other"})
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message", "message"])
        self.assertEqual(json.loads(frames[1]["data"]), {"action": "tail"})
        self.assertEqual(json.loads(frames[2]["data"]), {"action": "other"})

    def test_rearms_tail_after_unsubscribe_resubscribe_cycle(self):
        api = self._make_api()
        api.subscribe()
        api.unsubscribe()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual(
            [f["command"] for f in frames],
            ["subscribe", "message", "unsubscribe", "subscribe", "message"],
        )
        self.assertEqual(json.loads(frames[-1]["data"]), {"action": "tail"})


if __name__ == "__main__":
    unittest.main()
