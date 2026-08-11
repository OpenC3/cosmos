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
import os
import sys
import time
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from websockets.exceptions import ConnectionClosedOK

from openc3.script.exceptions import StopScriptError
from openc3.script.web_socket_api import (
    AllScriptsWebSocketApi,
    AutonomicEventsWebSocketApi,
    CalendarEventsWebSocketApi,
    CmdTlmWebSocketApi,
    ConfigEventsWebSocketApi,
    LimitsEventsWebSocketApi,
    MessagesWebSocketApi,
    QueueEventsWebSocketApi,
    RunningScriptWebSocketApi,
    ScriptWebSocketApi,
    StreamingWebSocketApi,
    SystemEventsWebSocketApi,
    TimelineEventsWebSocketApi,
    WebSocketApi,
)
from openc3.utilities.authentication import (
    OpenC3KeycloakAuthentication,
)
from openc3.utilities.time import to_nsec_from_epoch


class FakeWebSocketStream:
    """Stands in for the real TCP/WebSocket connection only -- everything above
    the socket (framing, subscription protocol, JSON) is exercised for real.
    Records what was written and replays a queued script of server frames."""

    def __init__(self, *init_args):
        self.init_args = init_args
        self.headers = None
        self._reads = []
        self.writes = []
        self.connect_count = 0
        self.disconnect_count = 0
        self._connected = False

    def queue_read(self, *messages):
        """Queue frames the "server" will return from read, in order"""
        self._reads.extend(messages)
        return self

    def connect(self):
        self.connect_count += 1
        self._connected = True

    def connected(self):
        return self._connected

    def disconnect(self):
        self.disconnect_count += 1
        self._connected = False

    def read(self):
        """Returns None once the queue drains, which the API treats as end-of-stream"""
        if not self._reads:
            return None
        return self._reads.pop(0)

    def write(self, data):
        self.writes.append(data)

    def frames(self):
        """The frames this client sent, parsed"""
        return [json.loads(w) for w in self.writes]


def mock_auth(token="test_token"):
    auth = Mock()
    auth.token.return_value = token
    return auth


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


class TestRunningScriptWebSocketApiReady(unittest.TestCase):
    """Verify the ready protocol: live script events only flow once the client
    performs the 'ready' channel action (see RunningScriptChannel#ready).
    subscribe() blocks until confirm_subscription, so sending 'ready'
    immediately after guarantees the gateway has registered the stream and the
    client cannot report ready in a way that races a broadcast."""

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

    def test_subscribe_reports_ready_exactly_once_after_confirmation(self):
        api = self._make_api()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message"])
        self.assertEqual(json.loads(frames[-1]["data"]), {"action": "ready"})

    def test_ready_action_identifier_matches_subscription(self):
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

    def test_no_ready_resend_on_subsequent_subscribes(self):
        api = self._make_api()
        api.subscribe()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message"])

    # write_action calls subscribe() internally, which on the first call is
    # the overridden subscribe that itself calls write_action for ready. Prove
    # this does not recurse or duplicate frames and preserves ordering.
    def test_action_triggering_first_subscribe_orders_subscribe_ready_action(self):
        api = self._make_api()
        api.write_action({"action": "other"})
        frames = self._frames(api)
        self.assertEqual([f["command"] for f in frames], ["subscribe", "message", "message"])
        self.assertEqual(json.loads(frames[1]["data"]), {"action": "ready"})
        self.assertEqual(json.loads(frames[2]["data"]), {"action": "other"})

    def test_reports_ready_again_after_unsubscribe_resubscribe_cycle(self):
        api = self._make_api()
        api.subscribe()
        api.unsubscribe()
        api.subscribe()
        frames = self._frames(api)
        self.assertEqual(
            [f["command"] for f in frames],
            ["subscribe", "message", "unsubscribe", "subscribe", "message"],
        )
        self.assertEqual(json.loads(frames[-1]["data"]), {"action": "ready"})


class TestWebSocketApiInit(unittest.TestCase):
    def test_stores_the_timeouts_for_the_stream(self):
        api = WebSocketApi(
            url="ws://test.com/cable",
            authentication=mock_auth(),
            write_timeout=1.0,
            read_timeout=2.0,
            connect_timeout=3.0,
        )
        self.assertEqual(api.write_timeout, 1.0)
        self.assertEqual(api.read_timeout, 2.0)
        self.assertEqual(api.connect_timeout, 3.0)
        self.assertFalse(api.subscribed)

    def test_defaults_the_scope_and_accepts_an_override(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        self.assertEqual(api.scope, "DEFAULT")
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth(), scope="OTHER")
        self.assertEqual(api.scope, "OTHER")

    def test_generates_authentication_when_none_is_passed(self):
        with patch.dict(os.environ, {"OPENC3_API_TOKEN": "token"}, clear=True):
            api = WebSocketApi(url="ws://test.com/cable")
            self.assertIsInstance(api.authentication, OpenC3KeycloakAuthentication)


class TestWebSocketApiContextManager(unittest.TestCase):
    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_connects_yields_itself_then_disconnects(self, stream_class):
        stream = FakeWebSocketStream()
        stream_class.return_value = stream
        with WebSocketApi(url="ws://test.com/cable", authentication=mock_auth()) as api:
            self.assertIsInstance(api, WebSocketApi)
            self.assertEqual(stream.connect_count, 1)
            self.assertTrue(api.connected())
        self.assertEqual(stream.disconnect_count, 1)

    # Guarantees a raising consumer block cannot leak the socket
    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_disconnects_even_when_the_block_raises(self, stream_class):
        stream = FakeWebSocketStream()
        stream_class.return_value = stream
        with (
            self.assertRaisesRegex(RuntimeError, "boom"),
            WebSocketApi(url="ws://test.com/cable", authentication=mock_auth()),
        ):
            raise RuntimeError("boom")
        self.assertEqual(stream.disconnect_count, 1)


class TestWebSocketApiConnect(unittest.TestCase):
    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_appends_the_scope_query_param_and_passes_the_timeouts(self, stream_class):
        stream = FakeWebSocketStream()
        stream_class.return_value = stream
        api = WebSocketApi(
            url="ws://test.com/cable",
            authentication=mock_auth(),
            scope="OTHER",
            write_timeout=1.0,
            read_timeout=2.0,
            connect_timeout=3.0,
        )
        api.connect()
        stream_class.assert_called_once_with("ws://test.com/cable?scope=OTHER", 1.0, 2.0, 3.0)
        self.assertEqual(stream.connect_count, 1)

    # The server negotiates the ActionCable JSON subprotocol from this header;
    # without it anycable-go refuses the upgrade.
    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_sets_the_actioncable_subprotocol_and_user_agent_headers(self, stream_class):
        stream = FakeWebSocketStream()
        stream_class.return_value = stream
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.connect()
        self.assertEqual(
            stream.headers["Sec-WebSocket-Protocol"],
            "actioncable-v1-json, actioncable-unsupported",
        )
        self.assertEqual(stream.headers["User-Agent"], WebSocketApi.USER_AGENT)

    @patch("openc3.script.web_socket_api.WebSocketClientStream")
    def test_disconnects_an_existing_connection_before_reconnecting(self, stream_class):
        stream = FakeWebSocketStream()
        stream_class.return_value = stream
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.connect()
        api.connect()
        self.assertEqual(stream.connect_count, 2)
        self.assertEqual(stream.disconnect_count, 1)


class TestWebSocketApiConnected(unittest.TestCase):
    def test_is_false_before_a_stream_exists(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        self.assertFalse(api.connected())

    def test_delegates_to_the_stream_once_connected(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        stream = FakeWebSocketStream()
        api.stream = stream
        self.assertFalse(api.connected())
        stream.connect()
        self.assertTrue(api.connected())


class TestWebSocketApiDisconnect(unittest.TestCase):
    def _make_api(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.stream = FakeWebSocketStream()
        return api

    def test_does_nothing_when_not_connected(self):
        api = self._make_api()
        api.disconnect()
        self.assertEqual(api.stream.disconnect_count, 0)

    def test_sends_unsubscribe_before_closing_the_stream(self):
        api = self._make_api()
        api.stream.connect()
        api.stream.queue_read('{"type":"confirm_subscription"}')
        api.subscribe()
        api.disconnect()
        self.assertEqual([f["command"] for f in api.stream.frames()], ["subscribe", "unsubscribe"])
        self.assertEqual(api.stream.disconnect_count, 1)
        self.assertFalse(api.subscribed)

    # A half-closed socket makes the courtesy unsubscribe fail; the close itself
    # must still happen or the socket leaks.
    def test_still_closes_the_stream_when_unsubscribe_raises(self):
        api = self._make_api()
        api.stream.connect()
        api.subscribed = True
        api.stream.write = Mock(side_effect=OSError("closed stream"))
        api.disconnect()
        self.assertEqual(api.stream.disconnect_count, 1)


class TestWebSocketApiUnsubscribe(unittest.TestCase):
    def _make_api(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.stream = FakeWebSocketStream()
        return api

    def test_writes_nothing_when_never_subscribed(self):
        api = self._make_api()
        api.unsubscribe()
        self.assertEqual(api.stream.writes, [])

    def test_writes_nothing_on_a_second_unsubscribe(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"confirm_subscription"}')
        api.subscribe()
        api.unsubscribe()
        api.unsubscribe()
        unsubscribes = [f for f in api.stream.frames() if f["command"] == "unsubscribe"]
        self.assertEqual(len(unsubscribes), 1)


class TestWebSocketApiRead(unittest.TestCase):
    def _make_api(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.stream = FakeWebSocketStream()
        # Skip the subscribe handshake; these tests exercise the data phase
        api.subscribed = True
        return api

    def test_parses_and_returns_message_content(self):
        api = self._make_api()
        api.stream.queue_read('{"message":{"level":"INFO","text":"test"}}')
        self.assertEqual(api.read(), {"level": "INFO", "text": "test"})

    # Empty frames are the normal end-of-stream signal when ActionCable /
    # anycable-go closes the connection. Returning None (rather than "") lets
    # canonical `while (resp := api.read())` consumer loops terminate cleanly.
    def test_returns_none_on_an_empty_frame(self):
        api = self._make_api()
        api.stream.queue_read("")
        self.assertIsNone(api.read())

    def test_returns_none_when_the_stream_is_drained(self):
        api = self._make_api()
        self.assertIsNone(api.read())

    def test_handles_an_empty_frame_after_valid_messages(self):
        api = self._make_api()
        api.stream.queue_read('{"message":{"data":"test"}}', "")
        self.assertEqual(api.read(), {"data": "test"})
        self.assertIsNone(api.read())

    # Defense-in-depth: a non-empty but malformed frame should not crash a
    # consumer -- surface it as end-of-stream.
    def test_returns_none_on_a_malformed_frame(self):
        api = self._make_api()
        api.stream.queue_read("not json{")
        self.assertIsNone(api.read())

    # A disconnect frame carrying no reason at all must not raise KeyError
    def test_ignores_a_disconnect_with_no_reason(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"disconnect"}', '{"message":{"data":"payload"}}')
        self.assertEqual(api.read(), {"data": "payload"})

    def test_ignores_protocol_messages_by_default(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}', '{"type":"welcome"}', '{"message":{"data":"actual_data"}}')
        self.assertEqual(api.read(), {"data": "actual_data"})

    def test_raises_on_disconnect_with_unauthorized(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"disconnect","reason":"unauthorized"}')
        with self.assertRaisesRegex(RuntimeError, "Unauthorized"):
            api.read()

    def test_raises_on_reject_subscription(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"reject_subscription"}')
        with self.assertRaisesRegex(RuntimeError, "Subscription Rejected"):
            api.read()

    def test_returns_protocol_messages_when_not_ignoring_them(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"welcome","message":{"server":"test"}}')
        self.assertEqual(api.read(ignore_protocol_messages=False), {"server": "test"})

    def test_returns_data_before_the_timeout_expires(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}', '{"message":{"data":"quick_response"}}')
        self.assertEqual(api.read(timeout=5.0), {"data": "quick_response"})


class TestWebSocketApiReadCooperativeStop(unittest.TestCase):
    """Inside Script Runner a blocking read on a quiet channel must still honor
    the user pressing Stop, hence the check on every protocol message."""

    def _make_api(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.stream = FakeWebSocketStream()
        api.subscribed = True
        return api

    def _patch_running_script(self, instance):
        """Install a fake running_script module so the lazy sys.modules lookup
        finds it without importing the real one"""
        module = Mock()
        module.RunningScript.instance = instance
        patcher = patch.dict(sys.modules, {"openc3.utilities.running_script": module})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_raises_stop_script_while_idling_on_protocol_messages(self):
        self._patch_running_script(Mock(stop=True))
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}')
        with self.assertRaises(StopScriptError):
            api.read()

    def test_keeps_reading_when_the_script_is_not_stopping(self):
        self._patch_running_script(Mock(stop=False))
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}', '{"message":{"data":"payload"}}')
        self.assertEqual(api.read(), {"data": "payload"})

    def test_does_not_check_for_stop_when_there_is_no_running_script_instance(self):
        self._patch_running_script(None)
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}', '{"message":{"data":"payload"}}')
        self.assertEqual(api.read(), {"data": "payload"})

    # Outside Script Runner the module was never imported, so the check is a
    # no-op and must not import it (which would be a cycle)
    def test_is_a_no_op_when_running_script_was_never_imported(self):
        patcher = patch.dict(sys.modules)
        patcher.start()
        self.addCleanup(patcher.stop)
        sys.modules.pop("openc3.utilities.running_script", None)
        api = self._make_api()
        api.stream.queue_read('{"type":"ping"}', '{"message":{"data":"payload"}}')
        self.assertEqual(api.read(), {"data": "payload"})
        self.assertNotIn("openc3.utilities.running_script", sys.modules)


class TestWebSocketApiWaitForSubscribed(unittest.TestCase):
    def _make_api(self):
        api = WebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        api.identifier = {"channel": "TestChannel"}
        api.stream = FakeWebSocketStream()
        return api

    def test_returns_on_confirmation_skipping_welcome_and_ping(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"welcome"}', '{"type":"ping"}', '{"type":"confirm_subscription"}')
        api.subscribe()
        self.assertTrue(api.subscribed)

    def test_raises_on_reject_subscription(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"reject_subscription"}')
        with self.assertRaisesRegex(RuntimeError, "Subscription Rejected"):
            api.subscribe()

    def test_raises_on_an_unauthorized_disconnect(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"disconnect","reason":"unauthorized"}')
        with self.assertRaisesRegex(RuntimeError, "Unauthorized"):
            api.subscribe()

    # A server-initiated disconnect for any other reason is not fatal here --
    # keep waiting rather than mistaking it for an auth failure.
    def test_keeps_waiting_on_a_disconnect_for_another_reason(self):
        api = self._make_api()
        api.stream.queue_read(
            '{"type":"disconnect","reason":"server_restart"}',
            '{"type":"confirm_subscription"}',
        )
        api.subscribe()
        self.assertTrue(api.subscribed)

    # Otherwise the client blocks forever reading None from a dead socket
    def test_raises_when_the_socket_closes_before_confirmation(self):
        api = self._make_api()
        api.stream.queue_read('{"type":"welcome"}')
        with self.assertRaisesRegex(RuntimeError, "WebSocket closed before subscription was confirmed"):
            api.subscribe()

    def test_raises_when_the_socket_returns_an_empty_frame(self):
        api = self._make_api()
        api.stream.queue_read("")
        with self.assertRaisesRegex(RuntimeError, "WebSocket closed before subscription was confirmed"):
            api.subscribe()


class TestWebSocketApiGenerateAuth(unittest.TestCase):
    def setUp(self):
        # Bypass __init__ so we test the auth selection alone
        self.api = WebSocketApi.__new__(WebSocketApi)

    def test_uses_password_authentication_when_only_the_password_is_set(self):
        # The real OpenC3Authentication constructor performs an HTTP token request
        with (
            patch.dict(os.environ, {"OPENC3_API_PASSWORD": "password"}, clear=True),
            patch("openc3.script.web_socket_api.OpenC3Authentication") as auth_class,
        ):
            auth_class.return_value = "core_auth"
            self.assertEqual(self.api._generate_auth(), "core_auth")

    # Failing fast beats returning None, which would only surface later as an
    # AttributeError inside subscribe(). Matches the Ruby client.
    def test_raises_when_no_authentication_environment_is_set(self):
        with (
            patch.dict(os.environ, {}, clear=True),
            self.assertRaisesRegex(RuntimeError, "Environment Variables Not Set for Authentication"),
        ):
            self.api._generate_auth()

    def test_uses_keycloak_authentication_when_the_api_token_is_set(self):
        env = {"OPENC3_API_TOKEN": "token", "OPENC3_KEYCLOAK_URL": "http://keycloak:8080"}
        with patch.dict(os.environ, env, clear=True):
            auth = self.api._generate_auth()
            self.assertIsInstance(auth, OpenC3KeycloakAuthentication)
            self.assertEqual(auth.url, "http://keycloak:8080")

    def test_uses_keycloak_authentication_when_the_api_user_is_set(self):
        env = {"OPENC3_API_USER": "user", "OPENC3_KEYCLOAK_URL": "http://keycloak:8080"}
        with patch.dict(os.environ, env, clear=True):
            self.assertIsInstance(self.api._generate_auth(), OpenC3KeycloakAuthentication)


class TestCmdTlmWebSocketApiGenerateUrl(unittest.TestCase):
    def setUp(self):
        self.api = CmdTlmWebSocketApi.__new__(CmdTlmWebSocketApi)

    def test_defaults_to_the_in_cluster_service_name_and_cable_port(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable")

    # Outside the cluster the service DNS name does not resolve
    def test_uses_localhost_when_openc3_devel_is_set(self):
        with patch.dict(os.environ, {"OPENC3_DEVEL": "../openc3"}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://127.0.0.1:3901/openc3-api/cable")

    def test_prefers_an_explicit_hostname_over_the_devel_default(self):
        env = {"OPENC3_DEVEL": "../openc3", "OPENC3_API_HOSTNAME": "example.com"}
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://example.com:3901/openc3-api/cable")

    # http/https are translated to the ws/wss websocket schemes
    def test_translates_the_http_schema_to_ws(self):
        with patch.dict(os.environ, {"OPENC3_API_SCHEMA": "http"}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable")

    def test_translates_the_https_schema_to_wss(self):
        with patch.dict(os.environ, {"OPENC3_API_SCHEMA": "https"}, clear=True):
            self.assertEqual(self.api.generate_url(), "wss://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable")

    def test_passes_an_unrecognized_schema_through(self):
        with patch.dict(os.environ, {"OPENC3_API_SCHEMA": "ws"}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable")

    def test_falls_back_to_the_api_port_when_no_cable_port_is_set(self):
        with patch.dict(os.environ, {"OPENC3_API_PORT": "2900"}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://openc3-cosmos-cmd-tlm-api:2900/openc3-api/cable")

    # Cable traffic can be routed to a different port than the REST API
    def test_prefers_the_cable_port_over_the_api_port(self):
        env = {"OPENC3_API_PORT": "2900", "OPENC3_API_CABLE_PORT": "3901"}
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://openc3-cosmos-cmd-tlm-api:3901/openc3-api/cable")

    def test_generates_its_url_when_none_is_given(self):
        env = {"OPENC3_API_HOSTNAME": "example.com", "OPENC3_API_CABLE_PORT": "1234"}
        with patch.dict(os.environ, env, clear=True):
            api = CmdTlmWebSocketApi(authentication=mock_auth())
            self.assertEqual(api.url, "ws://example.com:1234/openc3-api/cable")

    def test_uses_an_explicitly_passed_url_unchanged(self):
        api = CmdTlmWebSocketApi(url="ws://given:1/cable", authentication=mock_auth())
        self.assertEqual(api.url, "ws://given:1/cable")


class TestScriptWebSocketApiGenerateUrl(unittest.TestCase):
    def setUp(self):
        self.api = ScriptWebSocketApi.__new__(ScriptWebSocketApi)

    def test_defaults_to_the_in_cluster_script_runner_service_and_cable_port(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                self.api.generate_url(),
                "ws://openc3-cosmos-script-runner-api:3902/script-api/cable",
            )

    def test_uses_localhost_when_openc3_devel_is_set(self):
        with patch.dict(os.environ, {"OPENC3_DEVEL": "../openc3"}, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://127.0.0.1:3902/script-api/cable")

    def test_prefers_an_explicit_hostname_over_the_devel_default(self):
        env = {"OPENC3_DEVEL": "../openc3", "OPENC3_SCRIPT_API_HOSTNAME": "example.com"}
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(self.api.generate_url(), "ws://example.com:3902/script-api/cable")

    def test_translates_the_https_schema_to_wss(self):
        with patch.dict(os.environ, {"OPENC3_SCRIPT_API_SCHEMA": "https"}, clear=True):
            self.assertEqual(
                self.api.generate_url(),
                "wss://openc3-cosmos-script-runner-api:3902/script-api/cable",
            )

    def test_falls_back_to_the_script_api_port_when_no_cable_port_is_set(self):
        with patch.dict(os.environ, {"OPENC3_SCRIPT_API_PORT": "2900"}, clear=True):
            self.assertEqual(
                self.api.generate_url(),
                "ws://openc3-cosmos-script-runner-api:2900/script-api/cable",
            )

    def test_prefers_the_cable_port_over_the_script_api_port(self):
        env = {"OPENC3_SCRIPT_API_PORT": "2900", "OPENC3_SCRIPT_API_CABLE_PORT": "3902"}
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(
                self.api.generate_url(),
                "ws://openc3-cosmos-script-runner-api:3902/script-api/cable",
            )

    def test_generates_its_url_when_none_is_given(self):
        env = {"OPENC3_SCRIPT_API_HOSTNAME": "example.com", "OPENC3_SCRIPT_API_CABLE_PORT": "1234"}
        with patch.dict(os.environ, env, clear=True):
            api = ScriptWebSocketApi(authentication=mock_auth())
            self.assertEqual(api.url, "ws://example.com:1234/script-api/cable")


class TestChannelIdentifiers(unittest.TestCase):
    """The channel name in the identifier is what routes the subscription on the
    server, so a typo here silently yields a rejected or dead subscription."""

    HISTORY_COUNT_APIS = {
        AutonomicEventsWebSocketApi: "AutonomicEventsChannel",
        CalendarEventsWebSocketApi: "CalendarEventsChannel",
        ConfigEventsWebSocketApi: "ConfigEventsChannel",
        LimitsEventsWebSocketApi: "LimitsEventsChannel",
        SystemEventsWebSocketApi: "SystemEventsChannel",
        TimelineEventsWebSocketApi: "TimelineEventsChannel",
        QueueEventsWebSocketApi: "QueueEventsChannel",
    }

    def test_history_count_channels_default_history_count_to_zero(self):
        for klass, channel in self.HISTORY_COUNT_APIS.items():
            with self.subTest(klass=klass.__name__):
                api = klass(url="ws://test.com/cable", authentication=mock_auth())
                self.assertEqual(api.identifier, {"channel": channel, "history_count": 0})

    def test_history_count_channels_pass_history_count_through(self):
        for klass in self.HISTORY_COUNT_APIS:
            with self.subTest(klass=klass.__name__):
                api = klass(history_count=100, url="ws://test.com/cable", authentication=mock_auth())
                self.assertEqual(api.identifier["history_count"], 100)

    def test_history_count_channels_are_cmd_tlm_websockets(self):
        for klass in self.HISTORY_COUNT_APIS:
            with self.subTest(klass=klass.__name__):
                self.assertTrue(issubclass(klass, CmdTlmWebSocketApi))

    def test_all_scripts_channel(self):
        api = AllScriptsWebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        self.assertEqual(api.identifier, {"channel": "AllScriptsChannel"})
        self.assertTrue(issubclass(AllScriptsWebSocketApi, ScriptWebSocketApi))

    def test_running_script_channel_for_a_specific_script_id(self):
        api = RunningScriptWebSocketApi(id=42, url="ws://test.com/cable", authentication=mock_auth())
        self.assertEqual(api.identifier, {"channel": "RunningScriptChannel", "id": 42})
        self.assertTrue(issubclass(RunningScriptWebSocketApi, ScriptWebSocketApi))

    def test_messages_channel_omits_optional_filters_when_not_given(self):
        api = MessagesWebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        self.assertEqual(api.identifier, {"channel": "MessagesChannel", "history_count": 0})

    def test_messages_channel_includes_each_filter_that_is_given(self):
        api = MessagesWebSocketApi(
            history_count=10,
            start_time=1,
            end_time=2,
            level="INFO",
            types=["LOG"],
            url="ws://test.com/cable",
            authentication=mock_auth(),
        )
        self.assertEqual(
            api.identifier,
            {
                "channel": "MessagesChannel",
                "history_count": 10,
                "start_time": 1,
                "end_time": 2,
                "level": "INFO",
                "types": ["LOG"],
            },
        )

    def test_streaming_channel(self):
        api = StreamingWebSocketApi(url="ws://test.com/cable", authentication=mock_auth())
        self.assertEqual(api.identifier, {"channel": "StreamingChannel"})


class TestStreamingWebSocketApiActions(unittest.TestCase):
    def _make_api(self, scope=None):
        kwargs = {"scope": scope} if scope else {}
        api = StreamingWebSocketApi(url="ws://test.com/cable", authentication=mock_auth(), **kwargs)
        api.stream = FakeWebSocketStream()
        api.stream.queue_read('{"type":"confirm_subscription"}')
        return api

    def _action_data(self, api):
        """The action data hashes, i.e. what StreamingChannel add / remove receives"""
        return [json.loads(f["data"]) for f in api.stream.frames() if f["command"] == "message"]

    def test_add_sends_items_scope_and_token(self):
        api = self._make_api()
        api.add(items=["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"])
        self.assertEqual(
            self._action_data(api),
            [
                {
                    "action": "add",
                    "items": ["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"],
                    "scope": "DEFAULT",
                    "token": "test_token",
                }
            ],
        )

    def test_add_sends_packets_when_given(self):
        api = self._make_api()
        api.add(packets=["DECOM__TLM__INST__HEALTH_STATUS__CONVERTED"])
        data = self._action_data(api)[0]
        self.assertEqual(data["packets"], ["DECOM__TLM__INST__HEALTH_STATUS__CONVERTED"])
        self.assertNotIn("items", data)

    def test_add_omits_items_and_packets_when_neither_is_given(self):
        api = self._make_api()
        api.add()
        self.assertEqual(list(self._action_data(api)[0].keys()), ["action", "scope", "token"])

    # The channel expects 64-bit nanoseconds from the epoch, not a datetime
    def test_add_converts_datetimes_to_nanoseconds(self):
        api = self._make_api()
        start_time = datetime(2026, 1, 1, tzinfo=timezone.utc)
        end_time = datetime(2026, 1, 2, tzinfo=timezone.utc)
        api.add(items=["ITEM"], start_time=start_time, end_time=end_time)
        data = self._action_data(api)[0]
        self.assertEqual(data["start_time"], to_nsec_from_epoch(start_time))
        self.assertEqual(data["end_time"], to_nsec_from_epoch(end_time))

    def test_add_passes_integer_nanosecond_times_through_unchanged(self):
        api = self._make_api()
        api.add(items=["ITEM"], start_time=1_000_000_000, end_time=2_000_000_000)
        data = self._action_data(api)[0]
        self.assertEqual(data["start_time"], 1_000_000_000)
        self.assertEqual(data["end_time"], 2_000_000_000)

    def test_add_omits_the_times_when_not_given(self):
        api = self._make_api()
        api.add(items=["ITEM"])
        data = self._action_data(api)[0]
        self.assertNotIn("start_time", data)
        self.assertNotIn("end_time", data)

    def test_add_allows_overriding_the_scope_per_action(self):
        api = self._make_api()
        api.add(items=["ITEM"], scope="OTHER")
        self.assertEqual(self._action_data(api)[0]["scope"], "OTHER")

    # Regression: the default used to be the import-time OPENC3_SCOPE constant,
    # so an api built with an explicit scope still streamed from DEFAULT
    def test_add_defaults_to_the_scope_the_api_was_created_with(self):
        api = self._make_api(scope="OTHER")
        api.add(items=["ITEM"])
        self.assertEqual(self._action_data(api)[0]["scope"], "OTHER")

    def test_remove_defaults_to_the_scope_the_api_was_created_with(self):
        api = self._make_api(scope="OTHER")
        api.remove(items=["ITEM"])
        self.assertEqual(self._action_data(api)[0]["scope"], "OTHER")

    def test_add_subscribes_before_sending_the_action(self):
        api = self._make_api()
        api.add(items=["ITEM"])
        self.assertEqual([f["command"] for f in api.stream.frames()], ["subscribe", "message"])

    def test_remove_sends_items_scope_and_token(self):
        api = self._make_api()
        api.remove(items=["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"])
        self.assertEqual(
            self._action_data(api),
            [
                {
                    "action": "remove",
                    "items": ["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"],
                    "scope": "DEFAULT",
                    "token": "test_token",
                }
            ],
        )

    def test_remove_sends_packets_when_given(self):
        api = self._make_api()
        api.remove(packets=["DECOM__TLM__INST__HEALTH_STATUS__CONVERTED"])
        data = self._action_data(api)[0]
        self.assertEqual(data["packets"], ["DECOM__TLM__INST__HEALTH_STATUS__CONVERTED"])
        self.assertNotIn("items", data)

    def test_remove_allows_overriding_the_scope_per_action(self):
        api = self._make_api()
        api.remove(items=["ITEM"], scope="OTHER")
        self.assertEqual(self._action_data(api)[0]["scope"], "OTHER")


class TestStreamingWebSocketApiReadAll(unittest.TestCase):
    def setUp(self):
        self.stream = FakeWebSocketStream()
        # read_all takes no authentication argument, so _generate_auth runs;
        # patch only the network-touching constructor
        auth_patcher = patch("openc3.script.web_socket_api.OpenC3Authentication")
        auth_patcher.start().return_value = mock_auth()
        self.addCleanup(auth_patcher.stop)
        stream_patcher = patch("openc3.script.web_socket_api.WebSocketClientStream")
        stream_patcher.start().return_value = self.stream
        self.addCleanup(stream_patcher.stop)
        env_patcher = patch.dict(os.environ, {"OPENC3_API_PASSWORD": "password"}, clear=True)
        env_patcher.start()
        self.addCleanup(env_patcher.stop)

    # An empty batch is the end marker the streaming channel sends when the
    # requested time range is exhausted
    def test_concatenates_batches_until_an_empty_batch_ends_the_stream(self):
        self.stream.queue_read(
            '{"type":"confirm_subscription"}',
            '{"message":[{"__time":1},{"__time":2}]}',
            '{"message":[{"__time":3}]}',
            '{"message":[]}',
            '{"message":[{"__time":4}]}',  # must never be read
        )
        data = StreamingWebSocketApi.read_all(items=["ITEM"], end_time=datetime(2026, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(data, [{"__time": 1}, {"__time": 2}, {"__time": 3}])

    def test_sends_the_add_action_for_the_requested_range(self):
        start_time = datetime(2026, 1, 1, tzinfo=timezone.utc)
        end_time = datetime(2026, 1, 2, tzinfo=timezone.utc)
        self.stream.queue_read('{"type":"confirm_subscription"}', '{"message":[]}')
        StreamingWebSocketApi.read_all(items=["ITEM"], start_time=start_time, end_time=end_time, scope="OTHER")
        data = [json.loads(f["data"]) for f in self.stream.frames() if f["command"] == "message"]
        self.assertEqual(
            data[0],
            {
                "action": "add",
                "items": ["ITEM"],
                "start_time": to_nsec_from_epoch(start_time),
                "end_time": to_nsec_from_epoch(end_time),
                "scope": "OTHER",
                "token": "test_token",
            },
        )

    # Guards against blocking forever on a stream whose end marker never comes
    def test_returns_the_data_collected_so_far_once_the_timeout_elapses(self):
        self.stream.queue_read(
            '{"type":"confirm_subscription"}',
            '{"message":[{"__time":1}]}',
            '{"message":[{"__time":2}]}',
        )
        data = StreamingWebSocketApi.read_all(
            items=["ITEM"],
            end_time=datetime(2026, 1, 1, tzinfo=timezone.utc),
            timeout=0.0,
        )
        self.assertEqual(data, [{"__time": 1}])

    # Regression: this used to raise TypeError on len(None)
    def test_returns_the_data_collected_so_far_when_the_socket_closes_early(self):
        self.stream.queue_read(
            '{"type":"confirm_subscription"}',
            '{"message":[{"__time":1}]}',
            # Socket closes without ever sending the empty-batch end marker
        )
        data = StreamingWebSocketApi.read_all(items=["ITEM"], end_time=datetime(2026, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(data, [{"__time": 1}])

    def test_disconnects_the_stream_when_done(self):
        self.stream.queue_read('{"type":"confirm_subscription"}', '{"message":[]}')
        StreamingWebSocketApi.read_all(items=["ITEM"], end_time=datetime(2026, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(self.stream.disconnect_count, 1)


if __name__ == "__main__":
    unittest.main()
