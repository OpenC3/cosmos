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
from types import TracebackType
from typing import Any, TypeVar

from openc3.environment import OPENC3_SCOPE
from openc3.script.exceptions import StopScriptError
from openc3.streams.web_socket_client_stream import WebSocketClientStream
from openc3.utilities.authentication import authentication_from_environment
from openc3.utilities.time import to_nsec_from_epoch


# NOTE: For example usage see python/examples/cosmos_web_socket_example.py

_WebSocketApiT = TypeVar("_WebSocketApiT", bound="WebSocketApi")


def _nsec(value: datetime | int):
    """Accept either a datetime or an already converted 64-bit nanosecond value.

    Mirrors the Ruby client, which accepts a Time or an Integer.
    """
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


def _cable_url(env_prefix: str, default_hostname: str, default_port: str, path: str):
    """Build a cable URL from the standard OPENC3 environment variable quartet.

    The variables are <prefix>_SCHEMA, <prefix>_HOSTNAME, <prefix>_CABLE_PORT
    and <prefix>_PORT.
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
    """Base class for the COSMOS ActionCable websocket APIs. Do not use directly.

    Subclasses set ``self.identifier`` (the ActionCable channel identifier)
    before calling ``__init__``. Use an instance as a context manager to
    connect and disconnect::

        with StreamingWebSocketApi() as api:
            api.add(items=["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"])
            print(api.read())
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

    def __init__(self, url: str, scope: str = OPENC3_SCOPE, **options: Any) -> None:
        """Create the WebSocketApi object.

        Args:
            url: The cable URL to connect to.
            scope: The scope to connect with.
            **options: Any of DEFAULT_OPTIONS: write_timeout, read_timeout and
                connect_timeout in seconds, and authentication (an
                OpenC3Authentication; built from the environment when None).

        Raises:
            TypeError: If an option is not in DEFAULT_OPTIONS.
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

    def __enter__(self: _WebSocketApiT) -> _WebSocketApiT:
        """Connect and return this object."""
        self.connect()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None:
        """Disconnect."""
        self.disconnect()

    def read_message(self) -> str | bytes | None:
        """Read the next message without filtering or parsing. Subscribes first if needed.

        Returns:
            The raw message, or None if the read timed out or the server closed
            the connection.
        """
        self.subscribe()
        return self.stream.read()

    def read(self, ignore_protocol_messages: bool = True, timeout: float | None = None) -> Any:
        """Read the next message with JSON parsing, filtering, and timeout support.

        Args:
            ignore_protocol_messages: If True, ignore protocol messages like ping,
                welcome, confirm_subscription, reject_subscription, and disconnect.
            timeout: If set, raise TimeoutError if no data is received within
                this many seconds. None waits forever.

        Returns:
            The parsed "message" value of the next data frame (its shape
            depends on the channel), or None at end of stream.

        Raises:
            TimeoutError: If no data arrives within ``timeout`` seconds.
            StopScriptError: If the running Script Runner script is being stopped.
            RuntimeError: If the subscription is rejected or unauthorized.
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

    def subscribe(self) -> None:
        """Subscribe to the channel in ``self.identifier`` and wait for confirmation.

        Does nothing if already subscribed.

        Raises:
            RuntimeError: If the subscription is rejected, unauthorized, or the
                socket closes before it is confirmed.
        """
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

    def _check_protocol_frame(self, json_hash: dict[str, Any]):
        """Apply the protocol rules shared by read and _wait_for_subscribed."""
        msg_type = json_hash.get("type")
        if msg_type == "reject_subscription":
            raise RuntimeError("Subscription Rejected")
        # Any other disconnect reason is not fatal; the caller keeps reading
        if msg_type == "disconnect" and json_hash.get("reason") == "unauthorized":
            raise RuntimeError("Unauthorized")

    def _write_command(self, command: str, data_hash: dict[str, Any] | None = None):
        """Write an ActionCable command frame for the current identifier.

        Writes straight to the stream because the callers have already
        subscribed (and subscribe itself must not recurse through write).
        """
        json_hash = {}
        json_hash["command"] = command
        json_hash["identifier"] = json.dumps(self.identifier)
        if data_hash is not None:
            json_hash["data"] = json.dumps(data_hash)
        self.stream.write(json.dumps(json_hash))

    def unsubscribe(self) -> None:
        """Unsubscribe from the channel in ``self.identifier`` if subscribed."""
        if self.subscribed:
            self._write_command("unsubscribe")
            self.subscribed = False

    def write_action(self, data_hash: dict[str, Any]) -> None:
        """Send an ActionCable message command. Subscribes first if needed.

        Args:
            data_hash: The action data, including an "action" key.
        """
        # Subscribe first so the token is present in self.identifier before we
        # serialize it below. ActionCable matches a 'message' command to its
        # subscription by the exact identifier string; if subscribe() injected
        # the token only afterward, the message identifier (no token) would not
        # match the subscription identifier (with token) and the server would
        # silently ignore the action.
        self.subscribe()
        self._write_command("message", data_hash)

    def write(self, data: str | bytes) -> None:
        """Write raw data to the websocket. Subscribes first if needed.

        Args:
            data: The data to send.
        """
        self.subscribe()
        self.stream.write(data)

    def connect(self) -> bool:
        """Connect to the websocket, disconnecting any existing connection first.

        Returns:
            True once connected.
        """
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

    def connected(self) -> bool:
        """Return whether the websocket is connected."""
        if hasattr(self, "stream"):
            return self.stream.connected()
        else:
            return False

    def disconnect(self) -> None:
        """Disconnect from the websocket, attempting to unsubscribe first."""
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
        """Build the appropriate token for OpenC3."""
        authentication = authentication_from_environment()
        if authentication is None:
            raise RuntimeError("Environment Variables Not Set for Authentication")
        return authentication


class HistoryCountIdentifier:
    """Mixin for channels whose only parameter is the event history count.

    Including classes supply the channel name as a CHANNEL attribute.
    """

    CHANNEL = None

    def __init__(self, history_count: int = 0, **options: Any) -> None:
        """Set the channel identifier and initialize the websocket API.

        Args:
            history_count: Number of past events to send on subscribe.
            **options: Passed to the websocket API ``__init__`` (url, scope,
                and WebSocketApi.DEFAULT_OPTIONS).
        """
        self.identifier = {
            "channel": self.CHANNEL,
            "history_count": history_count,
        }
        super().__init__(**options)


class CmdTlmWebSocketApi(WebSocketApi):
    """Base class for cmd-tlm-api websockets. Do not use directly."""

    def __init__(self, url: str | None = None, **options: Any) -> None:
        """Create the websocket API.

        Args:
            url: The cable URL. Built from the environment when not given.
            **options: scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        if not url:
            url = self.generate_url()
        super().__init__(url=url, **options)

    def generate_url(self) -> str:
        """Build the cmd-tlm-api cable URL from OPENC3_API_* environment variables.

        Returns:
            The ws:// or wss:// cable URL.
        """
        return _cable_url(
            env_prefix="OPENC3_API",
            default_hostname="openc3-cosmos-cmd-tlm-api",
            default_port="3901",
            path="/openc3-api/cable",
        )


class ScriptWebSocketApi(WebSocketApi):
    """Base class for script-runner-api websockets. Do not use directly."""

    def __init__(self, url: str | None = None, **options: Any) -> None:
        """Create the websocket API.

        Args:
            url: The cable URL. Built from the environment when not given.
            **options: scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        if not url:
            url = self.generate_url()
        super().__init__(url=url, **options)

    def generate_url(self) -> str:
        """Build the script-runner-api cable URL from OPENC3_SCRIPT_API_* environment variables.

        Returns:
            The ws:// or wss:// cable URL.
        """
        return _cable_url(
            env_prefix="OPENC3_SCRIPT_API",
            default_hostname="openc3-cosmos-script-runner-api",
            default_port="3902",
            path="/script-api/cable",
        )


class RunningScriptWebSocketApi(ScriptWebSocketApi):
    """Stream the events of one running Script Runner script."""

    def __init__(self, id: int | str, **options: Any) -> None:
        """Create the websocket API.

        Args:
            id: The running script id.
            **options: url, scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        self.pending_events = deque()
        self.identifier = {"channel": "RunningScriptChannel", "id": id}
        super().__init__(**options)

    def subscribe(self) -> None:
        """Subscribe, then tell the server this client is ready for live events."""
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

    def read(self, ignore_protocol_messages: bool = True, timeout: float | None = None) -> Any:
        """Return one event at a time while accepting channel event batches.

        Args:
            ignore_protocol_messages: If True, ignore protocol messages like ping,
                welcome, confirm_subscription, reject_subscription, and disconnect.
            timeout: If set, raise TimeoutError if no data is received within
                this many seconds. None waits forever.

        Returns:
            The next script event, or None at end of stream.
        """
        if self.pending_events:
            return self.pending_events.popleft()

        while True:
            message = super().read(ignore_protocol_messages=ignore_protocol_messages, timeout=timeout)
            if not isinstance(message, list):
                return message
            self.pending_events.extend(message)
            if self.pending_events:
                return self.pending_events.popleft()

    def connect(self) -> bool:
        """Drop pending events and connect.

        Returns:
            True once connected.
        """
        self.pending_events.clear()
        return super().connect()

    def unsubscribe(self) -> None:
        """Drop pending events and unsubscribe."""
        self.pending_events.clear()
        return super().unsubscribe()

    def disconnect(self) -> None:
        """Drop pending events and disconnect."""
        self.pending_events.clear()
        return super().disconnect()


class AllScriptsWebSocketApi(ScriptWebSocketApi):
    """Stream events about all Script Runner scripts."""

    def __init__(self, **options: Any) -> None:
        """Create the websocket API.

        Args:
            **options: url, scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        self.identifier = {"channel": "AllScriptsChannel"}
        super().__init__(**options)


class MessagesWebSocketApi(CmdTlmWebSocketApi):
    """Stream log messages. Each read returns a batch (list) of messages."""

    def __init__(
        self,
        history_count: int = 0,
        start_time: int | None = None,
        end_time: int | None = None,
        level: str | None = None,
        types: list[str] | None = None,
        **options: Any,
    ) -> None:
        """Create the websocket API.

        Args:
            history_count: Number of past messages to send on subscribe.
            start_time: Start time in 64-bit nanoseconds from the unix epoch.
                Realtime when not given.
            end_time: End time in 64-bit nanoseconds from the unix epoch.
                Streams forever when not given.
            level: Minimum log level to return (e.g. "INFO").
            types: Message types to return.
            **options: url, scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        self.identifier: dict[str, Any] = {"channel": "MessagesChannel", "history_count": history_count}
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
    """Stream autonomic events (Enterprise only)."""

    CHANNEL = "AutonomicEventsChannel"


class CalendarEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream calendar events (Enterprise only)."""

    CHANNEL = "CalendarEventsChannel"


class ConfigEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream configuration change events."""

    CHANNEL = "ConfigEventsChannel"


class LimitsEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream limits events."""

    CHANNEL = "LimitsEventsChannel"


class SystemEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream system events."""

    CHANNEL = "SystemEventsChannel"


class TimelineEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream timeline events."""

    CHANNEL = "TimelineEventsChannel"


class QueueEventsWebSocketApi(HistoryCountIdentifier, CmdTlmWebSocketApi):
    """Stream command queue events."""

    CHANNEL = "QueueEventsChannel"


class StreamingWebSocketApi(CmdTlmWebSocketApi):
    """Stream telemetry and command data, realtime or historical."""

    def __init__(self, **options: Any) -> None:
        """Create the websocket API.

        Args:
            **options: url, scope and WebSocketApi.DEFAULT_OPTIONS.
        """
        self.identifier = {"channel": "StreamingChannel"}
        super().__init__(**options)

    def add(
        self,
        items: list[str | list[str]] | None = None,
        packets: list[str] | None = None,
        start_time: datetime | int | None = None,
        end_time: datetime | int | None = None,
        scope: str | None = None,
    ) -> None:
        """Request to add data to the stream.

        Item keys are MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE
        and packet keys are MODE__CMDORTLM__TARGET__PACKET__VALUETYPE, where:

        - MODE: RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
        - CMDORTLM: CMD or TLM
        - TARGET, PACKET, ITEM: target, packet and item names
        - VALUETYPE: RAW, CONVERTED, or FORMATTED (packets also accept PURE,
          meaning all types as stored in the log)
        - REDUCEDTYPE: MIN, MAX, AVG, STDDEV (only for reduced modes)

        Args:
            items: Item keys, or [item key, item_key] pairs where item_key is
                an optional shortened name to return the data as.
            packets: Packet keys.
            start_time: datetime or 64-bit nanoseconds from the unix epoch.
                Realtime when not given.
            end_time: datetime or 64-bit nanoseconds from the unix epoch.
                Streams forever when not given.
            scope: Scope name. Defaults to the scope this API was created with.
        """
        times = {}
        if start_time is not None:
            times["start_time"] = _nsec(start_time)
        if end_time is not None:
            times["end_time"] = _nsec(end_time)
        self._stream_action("add", items=items, packets=packets, scope=scope, extra=times)

    def remove(
        self,
        items: list[str | list[str]] | None = None,
        packets: list[str] | None = None,
        scope: str | None = None,
    ) -> None:
        """Request to remove data from the stream.

        See `add` for the item and packet key formats.

        Args:
            items: Item keys to remove.
            packets: Packet keys to remove.
            scope: Scope name. Defaults to the scope this API was created with.
        """
        self._stream_action("remove", items=items, packets=packets, scope=scope)

    def _stream_action(
        self,
        action: str,
        items: list[str | list[str]] | None = None,
        packets: list[str] | None = None,
        scope: str | None = None,
        extra: dict[str, Any] | None = None,
    ):
        """Build and write a StreamingChannel action.

        extra carries action specific keys (the times for add) and is merged
        first to preserve wire ordering.
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
    def read_all(
        cls,
        items: list[str | list[str]] | None = None,
        packets: list[str] | None = None,
        start_time: datetime | int | None = None,
        end_time: datetime | int | None = None,
        scope: str | None = None,
        timeout: float | None = None,
    ) -> list[Any]:
        """Read all data until the end marker is received.

        Omitting end_time streams realtime and endlessly: no end marker is ever
        sent, so a timeout is the only way the collection ends on its own.

        Warning: DATA IS STORED IN RAM. Do not use this with large queries.

        Args:
            items: Item keys, see `add`.
            packets: Packet keys, see `add`.
            start_time: datetime or 64-bit nanoseconds from the unix epoch.
                Realtime when not given.
            end_time: datetime or 64-bit nanoseconds from the unix epoch.
                Streams forever when not given.
            scope: Scope name. Defaults to OPENC3_SCOPE.
            timeout: Stop after this many seconds. None waits for the end marker.

        Returns:
            The data entries from every batch received.

        Raises:
            RuntimeError: If end_time is given and the socket closes before the
                end marker.
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
