# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import contextlib
import json
import os
import sys
import time
from collections import deque
from datetime import datetime

from openc3.environment import OPENC3_SCOPE
from openc3.script.exceptions import StopScriptError
from openc3.streams.web_socket_client_stream import WebSocketClientStream
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)
from openc3.utilities.time import to_nsec_from_epoch


# NOTE: For example usage see python/examples/cosmos_web_socket_example.py


def _nsec(value):
    """Accept either a datetime or an already converted 64-bit nanosecond value
    (mirrors the Ruby client, which accepts a Time or an Integer)"""
    if isinstance(value, datetime):
        return to_nsec_from_epoch(value)
    return value


def _stopping():
    """True if a Script Runner script is being stopped.

    Looks the module up in sys.modules rather than importing it so this stays a
    no-op outside of Script Runner and cannot create an import cycle (same
    pattern as openc3.utilities.string).
    """
    module = sys.modules.get("openc3.utilities.running_script")
    if module is None:
        return False
    instance = getattr(module.RunningScript, "instance", None)
    return bool(instance and instance.stop)


def _cable_url(env_prefix, default_hostname, default_port, path):
    """Build a cable URL from the standard OPENC3 environment variable quartet:
    <prefix>_SCHEMA, <prefix>_HOSTNAME, <prefix>_CABLE_PORT, <prefix>_PORT
    """
    schema = os.environ.get(f"{env_prefix}_SCHEMA") or "http"
    # Normalize to the websocket schemes; the websockets library rejects http
    if schema == "http":
        schema = "ws"
    if schema == "https":
        schema = "wss"
    hostname = os.environ.get(f"{env_prefix}_HOSTNAME") or (
        "127.0.0.1" if os.environ.get("OPENC3_DEVEL") else default_hostname
    )
    port = os.environ.get(f"{env_prefix}_CABLE_PORT") or os.environ.get(f"{env_prefix}_PORT") or default_port
    return f"{schema}://{hostname}:{int(port)}{path}"


class WebSocketApi:
    """
    Base class - Do not use directly
    """

    USER_AGENT = "OpenC3 / v7 (ruby/openc3/lib/io/web_socket_api)"

    # Options every websocket api accepts, and their defaults. Subclasses
    # forward **options rather than restating these.
    DEFAULT_OPTIONS = {
        "write_timeout": 10.0,
        "read_timeout": 10.0,
        "connect_timeout": 5.0,
        "authentication": None,
    }

    def __init__(self, url, scope=OPENC3_SCOPE, **options):
        """Create the WebsocketApi object

        Args:
            url (str): The cable URL to connect to
            scope (str): The scope to connect with
            options: See DEFAULT_OPTIONS
        """
        # Restore the arity checking that explicit keyword arguments used to
        # give us, so a typo'd option is an error rather than a silently
        # ignored value
        unknown = sorted(set(options) - set(self.DEFAULT_OPTIONS))
        if unknown:
            raise TypeError(f"unexpected keyword argument(s): {', '.join(unknown)}")
        options = {**self.DEFAULT_OPTIONS, **options}
        self.scope = scope
        self.authentication = options["authentication"] or self._generate_auth()
        self.url = url
        self.write_timeout = options["write_timeout"]
        self.read_timeout = options["read_timeout"]
        self.connect_timeout = options["connect_timeout"]
        self.subscribed = False

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()

    def read_message(self):
        """Read the next message without filtering / parsing"""
        self.subscribe()
        return self.stream.read()

    def read(self, ignore_protocol_messages=True, timeout=None):
        """
        Read the next message with json parsing, filtering, and timeout support

        Args:
            ignore_protocol_messages (bool): If True, will ignore protocol messages like ping, welcome,
                confirm_subscription, reject_subscription, and disconnect. Default is True.
            timeout (float): If set, will raise TimeoutError if no data is received within the specified
                number of seconds. Default is None (no timeout).
        """
        start_time = time.time()
        while True:
            message = self.read_message()
            # Empty string is a normal end-of-stream signal when ActionCable /
            # anycable-go closes the WS. Normalize it to None so consumer
            # `while (resp := api.read())` loops exit cleanly.
            if not message:
                return None

            json_hash = json.loads(message)

            if ignore_protocol_messages:
                msg_type = json_hash.get("type")
                if msg_type:  # ping, welcome, confirm_subscription, reject_subscription, disconnect
                    self._check_protocol_frame(json_hash)
                    if timeout is not None:
                        end_time = time.time()
                        if (end_time - start_time) > timeout:
                            raise TimeoutError("No Data Timeout")
                    if _stopping():
                        raise StopScriptError
                    continue
            return json_hash["message"]

    def subscribe(self):
        """Will subscribe to the channel based on @identifier"""
        if not self.subscribed:
            # Token is part of the identifier so it surfaces as params[:token]
            # in ApplicationCable::Channel#authenticate_subscription! —
            # ActionCable ignores `data` on `subscribe` commands.
            self.identifier["token"] = self.authentication.token(include_bearer=False)
            self._write_command("subscribe")
            self.subscribed = True
            self._wait_for_subscribed()

    def _wait_for_subscribed(self):
        """Block until the server confirms the subscription.

        ActionCable / anycable-go process 'subscribe' and 'message' commands as
        independent RPCs, so an action (add/remove) written immediately after
        subscribe can reach StreamingChannel#add before the subscription's
        broadcaster exists, where it is silently dropped (a no-op) and no data
        ever streams. Waiting for confirm_subscription guarantees the broadcaster
        is ready before any action is written.
        """
        while True:
            message = self.stream.read()
            # Unlike read, end-of-stream is fatal here rather than a None
            # return: a socket that closes mid-handshake leaves nothing to
            # carry on with.
            if not message:
                raise RuntimeError("WebSocket closed before subscription was confirmed")
            json_hash = json.loads(message)
            self._check_protocol_frame(json_hash)
            # Ignore welcome / ping and keep waiting for confirmation
            if json_hash.get("type") == "confirm_subscription":
                return

    def _check_protocol_frame(self, json_hash):
        """Apply the protocol rules shared by read and _wait_for_subscribed"""
        msg_type = json_hash.get("type")
        if msg_type == "reject_subscription":
            raise RuntimeError("Subscription Rejected")
        # Any other disconnect reason is not fatal; the caller keeps reading
        if msg_type == "disconnect" and json_hash.get("reason") == "unauthorized":
            raise RuntimeError("Unauthorized")

    def _write_command(self, command, data_hash=None):
        """Write an ActionCable command frame for the current identifier. Writes
        straight to the stream because the callers have already subscribed (and
        subscribe itself must not recurse through write).
        """
        json_hash = {}
        json_hash["command"] = command
        json_hash["identifier"] = json.dumps(self.identifier)
        if data_hash is not None:
            json_hash["data"] = json.dumps(data_hash)
        self.stream.write(json.dumps(json_hash))

    def unsubscribe(self):
        """Will unsubscribe to the channel based on @identifier"""
        if self.subscribed:
            self._write_command("unsubscribe")
            self.subscribed = False

    def write_action(self, data_hash):
        """Send an ActionCable command"""
        # Subscribe first so the token is present in self.identifier before we
        # serialize it below. ActionCable matches a 'message' command to its
        # subscription by the exact identifier string; if subscribe() injected
        # the token only afterward, the message identifier (no token) would not
        # match the subscription identifier (with token) and the server would
        # silently ignore the action.
        self.subscribe()
        self._write_command("message", data_hash)

    def write(self, data):
        """General write to the websocket"""
        self.subscribe()
        self.stream.write(data)

    def connect(self):
        """Connect to the websocket with authorization in query params"""
        self.disconnect()
        # Add the token directly in the URL since adding it to the header doesn't seem to work
        # Note in the this case we remove the "Bearer " string which is part of the token
        final_url = self.url + f"?scope={self.scope}"
        self.stream = WebSocketClientStream(final_url, self.write_timeout, self.read_timeout, self.connect_timeout)
        self.stream.headers = {
            "Sec-WebSocket-Protocol": "actioncable-v1-json, actioncable-unsupported",
            "User-Agent": WebSocketApi.USER_AGENT,
            # Adding the authorization token to the header is supposed to work
            # We add it directly with "Bearer <token>"
            # But for some reason it doesn't so we add it directly to the URL above
            # "Authorization": self.authentication.token(include_bearer=False),
        }
        return self.stream.connect()

    def connected(self):
        """Are we connected?"""
        if hasattr(self, "stream"):
            return self.stream.connected()
        else:
            return False

    def disconnect(self):
        """Disconnect from the websocket and attempt to send unsubscribe message"""
        if self.connected():
            # A half-closed socket makes the courtesy unsubscribe fail; the
            # close itself must still happen or the socket leaks.
            with contextlib.suppress(Exception):
                self.unsubscribe()
            # unsubscribe only clears this after a successful write. The stream
            # is being closed regardless, so it cannot remain subscribed.
            self.subscribed = False
            self.stream.disconnect()
        else:
            self.subscribed = False

    def _generate_auth(self):
        """Generate the appropriate token for OpenC3"""
        if os.environ.get("OPENC3_API_TOKEN") is None and os.environ.get("OPENC3_API_USER") is None:
            if os.environ.get("OPENC3_API_PASSWORD"):
                return OpenC3Authentication()
            else:
                raise RuntimeError("Environment Variables Not Set for Authentication")
        else:
            return OpenC3KeycloakAuthentication(os.environ.get("OPENC3_KEYCLOAK_URL"))


class HistoryCountIdentifier:
    """Identifier for channels whose only parameter is the event history count.
    Including classes supply the channel name as a CHANNEL attribute.
    """

    CHANNEL = None

    def __init__(self, history_count=0, **options):
        self.identifier = {
            "channel": self.CHANNEL,
            "history_count": history_count,
        }
        super().__init__(**options)


class CmdTlmWebSocketApi(WebSocketApi):
    """Base class for cmd-tlm-api websockets - Do not use directly"""

    def __init__(self, url=None, **options):
        if not url:
            url = self.generate_url()
        super().__init__(url=url, **options)

    def generate_url(self):
        return _cable_url(
            env_prefix="OPENC3_API",
            default_hostname="openc3-cosmos-cmd-tlm-api",
            default_port="3901",
            path="/openc3-api/cable",
        )


class ScriptWebSocketApi(WebSocketApi):
    """Base class for script-runner-api websockets - Do not use directly"""

    def __init__(self, url=None, **options):
        if not url:
            url = self.generate_url()
        super().__init__(url=url, **options)

    def generate_url(self):
        return _cable_url(
            env_prefix="OPENC3_SCRIPT_API",
            default_hostname="openc3-cosmos-script-runner-api",
            default_port="3902",
            path="/script-api/cable",
        )


class RunningScriptWebSocketApi(ScriptWebSocketApi):
    """Running Script WebSocket"""

    def __init__(self, id, **options):
        self.pending_events = deque()
        self.identifier = {"channel": "RunningScriptChannel", "id": id}
        super().__init__(**options)

    def subscribe(self):
        # The backlog of script events is transmitted with the subscription
        # confirmation, but LIVE events only flow once the client reports that
        # it is ready to stream events (see RunningScriptChannel#ready) -- a
        # broadcast sent before the gateway has registered this subscription's
        # stream would be silently dropped. subscribe() blocks until
        # confirm_subscription, so the 'ready' action is guaranteed to arrive
        # after the stream is registered.
        was_subscribed = self.subscribed
        super().subscribe()
        if not was_subscribed:
            self.write_action({"action": "ready"})

    def read(self, ignore_protocol_messages=True, timeout=None):
        """Return one event at a time while accepting channel event batches."""
        if self.pending_events:
            return self.pending_events.popleft()

        while True:
            message = super().read(ignore_protocol_messages=ignore_protocol_messages, timeout=timeout)
            if not isinstance(message, list):
                return message
            self.pending_events.extend(message)
            if self.pending_events:
                return self.pending_events.popleft()

    def connect(self):
        self.pending_events.clear()
        return super().connect()

    def unsubscribe(self):
        self.pending_events.clear()
        return super().unsubscribe()

    def disconnect(self):
        self.pending_events.clear()
        return super().disconnect()


class AllScriptsWebSocketApi(ScriptWebSocketApi):
    """All Scripts WebSocket"""

    def __init__(self, **options):
        self.identifier = {"channel": "AllScriptsChannel"}
        super().__init__(**options)


class MessagesWebSocketApi(CmdTlmWebSocketApi):
    """Log Messages WebSocket"""

    def __init__(self, history_count=0, start_time=None, end_time=None, level=None, types=None, **options):
        self.identifier = {"channel": "MessagesChannel", "history_count": history_count}
        if start_time is not None:
            self.identifier["start_time"] = start_time
        if end_time is not None:
            self.identifier["end_time"] = end_time
        if level is not None:
            self.identifier["level"] = level
        if types is not None:
            self.identifier["types"] = types
        super().__init__(**options)


class AutonomicEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Autonomic Events WebSocket (Enterprise Only)"""

    CHANNEL = "AutonomicEventsChannel"


class CalendarEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Calendar Events WebSocket (Enterprise Only)"""

    CHANNEL = "CalendarEventsChannel"


class ConfigEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Config Events WebSocket"""

    CHANNEL = "ConfigEventsChannel"


class LimitsEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Limits Events WebSocket"""

    CHANNEL = "LimitsEventsChannel"


class SystemEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """System Events WebSocket"""

    CHANNEL = "SystemEventsChannel"


class TimelineEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Timeline WebSocket"""

    CHANNEL = "TimelineEventsChannel"


class QueueEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Queue WebSocket"""

    CHANNEL = "QueueEventsChannel"


class StreamingWebSocketApi(CmdTlmWebSocketApi):
    """Streaming API WebSocket"""

    def __init__(self, **options):
        self.identifier = {"channel": "StreamingChannel"}
        super().__init__(**options)

    def add(self, items=None, packets=None, start_time=None, end_time=None, scope=None):
        """
        Request to add data to the stream

        Args:
            items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE, item_key] ]
                MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
                CMDORTLM - CMD or TLM
                TARGET - Target name
                PACKET - Packet name
                ITEM - Item Name
                VALUETYPE - RAW, CONVERTED, or FORMATTED
                REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
                item_key is an optional shortened name to return the data as
            packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
                MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
                CMDORTLM - CMD or TLM
                TARGET - Target name
                PACKET - Packet name
                VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
            start_time: datetime or 64-bit nanoseconds from unix epoch - If not present then realtime
            end_time: datetime or 64-bit nanoseconds from unix epoch - If not present stream forever
            scope: scope name - defaults to the scope this api was created with
        """
        times = {}
        if start_time is not None:
            times["start_time"] = _nsec(start_time)
        if end_time is not None:
            times["end_time"] = _nsec(end_time)
        self._stream_action("add", items=items, packets=packets, scope=scope, extra=times)

    def remove(self, items=None, packets=None, scope=None):
        """
        Request to remove data from the stream

        Args:
            items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE] ]
                MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
                CMDORTLM - CMD or TLM
                TARGET - Target name
                PACKET - Packet name
                ITEM - Item Name
                VALUETYPE - RAW, CONVERTED, or FORMATTED
                REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
            packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
                MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
                CMDORTLM - CMD or TLM
                TARGET - Target name
                PACKET - Packet name
                VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
            scope: scope name - defaults to the scope this api was created with
        """
        self._stream_action("remove", items=items, packets=packets, scope=scope)

    def _stream_action(self, action, items=None, packets=None, scope=None, extra=None):
        """Build and write a StreamingChannel action. extra carries action
        specific keys (the times for add) and is merged first to preserve wire
        ordering.
        """
        data_hash = {}
        data_hash["action"] = action
        if extra:
            data_hash.update(extra)
        if items:
            data_hash["items"] = items
        if packets:
            data_hash["packets"] = packets
        data_hash["scope"] = self.scope if scope is None else scope
        data_hash["token"] = self.authentication.token(include_bearer=False)
        self.write_action(data_hash)

    @classmethod
    def read_all(cls, items=None, packets=None, start_time=None, end_time=None, scope=None, timeout=None):
        """
        Convenience method to read all data until end marker is received.

        Omitting end_time streams realtime and endlessly: no end marker is ever
        sent, so a timeout is the only way the collection ends on its own.

        Warning: DATA IS STORED IN RAM. Do not use this with large queries
        """
        read_all_start_time = time.time()
        data = []
        with cls() as api:
            api.add(
                items=items,
                packets=packets,
                start_time=start_time,
                end_time=end_time,
                scope=scope,
            )
            while True:
                batch = api.read()
                if batch is None:
                    # A bounded query must receive its end marker; a truncated
                    # result returned as if complete is worse than an error. A
                    # realtime query never gets one, so a close is an ordinary
                    # way for it to end.
                    if end_time is not None:
                        raise RuntimeError("WebSocket closed before end marker")
                    break
                # An empty batch is the explicit end marker sent after a
                # historical query is complete.
                if len(batch) == 0:
                    break
                data += batch
                if timeout is not None and (time.time() - read_all_start_time) > timeout:
                    break
        return data
