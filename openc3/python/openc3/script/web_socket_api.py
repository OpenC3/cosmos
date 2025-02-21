# Copyright 2023 OpenC3, Inc.
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

import os
import time
import json
from openc3.streams.web_socket_client_stream import WebSocketClientStream
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)
from openc3.utilities.time import to_nsec_from_epoch
from openc3.environment import OPENC3_SCOPE


# NOTE: For example usage see python/examples/cosmos_web_socket_example.py


# Base class - Do not use directly
class WebSocketApi:
    USER_AGENT = "OpenC3 / v5 (ruby/openc3/lib/io/web_socket_api)"

    # Create the WebsocketApi object
    def __init__(
        self,
        url,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.scope = scope
        if authentication is None:
            self.authentication = self._generate_auth()
        else:
            self.authentication = authentication
        self.url = url
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        self.connect_timeout = connect_timeout
        self.subscribed = False

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()

    # Read the next message without filtering / parsing
    def read_message(self):
        self.subscribe()
        return self.stream.read()

    # Read the next message with json parsing, filtering, and timeout support
    def read(self, ignore_protocol_messages=True, timeout=None):
        start_time = time.time()
        while True:
            message = self.read_message()
            if message:
                json_hash = json.loads(message)
                if ignore_protocol_messages:
                    msg_type = json_hash.get("type")
                    if msg_type:  # ping, welcome, confirm_subscription, reject_subscription, disconnect
                        if msg_type == "disconnect":
                            if json_hash["reason"] == "unauthorized":
                                raise RuntimeError("Unauthorized")
                        if msg_type == "reject_subscription":
                            raise RuntimeError("Subscription Rejected")
                        if timeout:
                            end_time = time.time()
                            if (start_time - end_time) > timeout:
                                raise TimeoutError("No Data Timeout")
                        # if defined? RunningScript and RunningScript.instance:
                        #   if RunningScript.instance.stop?:
                        #       raise StopScript
                        continue
                return json_hash["message"]
            return message

    # Will subscribe to the channel based on @identifier
    def subscribe(self):
        if not self.subscribed:
            json_hash = {}
            json_hash["command"] = "subscribe"
            json_hash["identifier"] = json.dumps(self.identifier)
            self.stream.write(json.dumps(json_hash))
            self.subscribed = True

    # Will unsubscribe to the channel based on @identifier
    def unsubscribe(self):
        if self.subscribed:
            json_hash = {}
            json_hash["command"] = "unsubscribe"
            json_hash["identifier"] = json.dumps(self.identifier)
            self.stream.write(json.dumps(json_hash))
            self.subscribed = False

    # Send an ActionCable command
    def write_action(self, data_hash):
        json_hash = {}
        json_hash["command"] = "message"
        json_hash["identifier"] = json.dumps(self.identifier)
        json_hash["data"] = json.dumps(data_hash)
        self.write(json.dumps(json_hash))

    # General write to the websocket
    def write(self, data):
        self.subscribe()
        self.stream.write(data)

    # Connect to the websocket with authorization in query params
    def connect(self):
        self.disconnect()
        # Add the token directly in the URL since adding it to the header doesn't seem to work
        # Note in the this case we remove the "Bearer " string which is part of the token
        final_url = self.url + f"?scope={self.scope}&authorization={self.authentication.token(include_bearer=False)}"
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

    # Are we connected?
    def connected(self):
        if hasattr(self, "stream"):
            return self.stream.connected()
        else:
            return False

    # Disconnect from the websocket and attempt to send unsubscribe message
    def disconnect(self):
        if self.connected():
            self.unsubscribe()
            self.stream.disconnect()

    # Generate the appropriate token for OpenC3
    def _generate_auth(self):
        if os.environ.get("OPENC3_API_TOKEN") is None and os.environ.get("OPENC3_API_USER") is None:
            if os.environ.get("OPENC3_API_PASSWORD"):
                return OpenC3Authentication()
            else:
                return None
        else:
            return OpenC3KeycloakAuthentication(os.environ.get("OPENC3_KEYCLOAK_URL"))


# Base class for cmd-tlm-api websockets - Do not use directly
class CmdTlmWebSocketApi(WebSocketApi):
    def __init__(
        self,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        if not url:
            url = self.generate_url()
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )

    def generate_url(self):
        schema = os.environ.get("OPENC3_API_SCHEMA") or "http"
        if schema == "http":
            schema = "ws"
        if schema == "https":
            schema = "wss"
        hostname = os.environ.get("OPENC3_API_HOSTNAME") or (
            "127.0.0.1" if os.environ.get("OPENC3_DEVEL") else "openc3-cosmos-cmd-tlm-api"
        )
        port = os.environ.get("OPENC3_API_CABLE_PORT") or os.environ.get("OPENC3_API_PORT") or "3901"
        port = int(port)
        return f"{schema}://{hostname}:{port}/openc3-api/cable"


# Base class for script-runner-api websockets - Do not use directly
class ScriptWebSocketApi(WebSocketApi):
    def __init__(
        self,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        if not url:
            url = self.generate_url()
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )

    def generate_url(self):
        schema = os.environ.get("OPENC3_SCRIPT_API_SCHEMA") or "http"
        if schema == "http":
            schema = "ws"
        if schema == "https":
            schema = "wss"
        hostname = os.environ.get("OPENC3_SCRIPT_API_HOSTNAME") or (
            "127.0.0.1" if os.environ.get("OPENC3_DEVEL") else "openc3-cosmos-script-runner-api"
        )
        port = os.environ.get("OPENC3_SCRIPT_API_CABLE_PORT") or os.environ.get("OPENC3_SCRIPT_API_PORT") or "3902"
        port = int(port)
        return f"{schema}://{hostname}:{port}/script-api/cable"


# Running Script WebSocket
class RunningScriptWebSocketApi(ScriptWebSocketApi):
    def __init__(
        self,
        id,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {"channel": "RunningScriptChannel", "id": id}
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# All Scripts WebSocket
class AllScriptsWebSocketApi(ScriptWebSocketApi):
    def __init__(
        self,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {"channel": "AllScriptsChannel"}
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Log Messages WebSocket
class MessagesWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        start_time=None,
        end_time=None,
        level=None,
        types=None,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {"channel": "MessagesChannel", "history_count": history_count}
        if start_time:
            self.identifier["start_time"] = start_time
        if end_time:
            self.identifier["end_time"] = end_time
        if level:
            self.identifier["level"] = level
        if types:
            self.identifier["types"] = types
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Autonomic Events WebSocket (Enterprise Only)
class AutonomicEventsWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {
            "channel": "AutonomicEventsChannel",
            "history_count": history_count,
        }
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Calendar Events WebSocket (Enterprise Only)
class CalendarEventsWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {
            "channel": "CalendarEventsChannel",
            "history_count": history_count,
        }
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Config Events WebSocket
class ConfigEventsWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {
            "channel": "ConfigEventsChannel",
            "history_count": history_count,
        }
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Limits Events WebSocket
class LimitsEventsWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {
            "channel": "LimitsEventsChannel",
            "history_count": history_count,
        }
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Timeline WebSocket
class TimelineEventsWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        history_count=0,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {
            "channel": "TimelineEventsChannel",
            "history_count": history_count,
        }
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )


# Streaming API WebSocket
class StreamingWebSocketApi(CmdTlmWebSocketApi):
    def __init__(
        self,
        url=None,
        write_timeout=10.0,
        read_timeout=10.0,
        connect_timeout=5.0,
        authentication=None,
        scope=OPENC3_SCOPE,
    ):
        self.identifier = {"channel": "StreamingChannel"}
        super().__init__(
            url=url,
            write_timeout=write_timeout,
            read_timeout=read_timeout,
            connect_timeout=connect_timeout,
            authentication=authentication,
            scope=scope,
        )

    # Request to add data to the stream
    #
    # arguments:
    # scope: scope name
    # start_time: 64-bit nanoseconds from unix epoch - If not present then realtime
    # end_time: 64-bit nanoseconds from unix epoch - If not present stream forever
    # items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE, item_key] ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   ITEM - Item Name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    #   item_key is an optional shortened name to return the data as
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
    #
    def add(
        self,
        items=None,
        packets=None,
        start_time=None,
        end_time=None,
        scope=OPENC3_SCOPE,
    ):
        data_hash = {}
        data_hash["action"] = "add"
        if start_time:
            data_hash["start_time"] = to_nsec_from_epoch(start_time)
        if end_time:
            data_hash["end_time"] = to_nsec_from_epoch(end_time)
        if items:
            data_hash["items"] = items
        if packets:
            data_hash["packets"] = packets
        data_hash["scope"] = scope
        data_hash["token"] = self.authentication.token(include_bearer=False)
        self.write_action(data_hash)

    # Request to remove data from the stream
    #
    # arguments:
    # scope: scope name
    # items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE] ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   ITEM - Item Name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
    #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
    # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
    #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
    #   CMDORTLM - CMD or TLM
    #   TARGET - Target name
    #   PACKET - Packet name
    #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
    #
    def remove(self, items=None, packets=None, scope=OPENC3_SCOPE):
        data_hash = {}
        data_hash["action"] = "remove"
        if items:
            data_hash["items"] = items
        if packets:
            data_hash["packets"] = packets
        data_hash["scope"] = scope
        data_hash["token"] = self.authentication.token(include_bearer=False)
        self.write_action(data_hash)

    # Convenience method to read all data until end marker is received.
    # Warning: DATA IS STORED IN RAM.  Do not use this with large queries
    @classmethod
    def read_all(
        cls,
        items=None,
        packets=None,
        start_time=None,
        end_time=None,
        scope=OPENC3_SCOPE,
        timeout=None,
    ):
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
                if len(batch) == 0:
                    break
                else:
                    data += batch
                if timeout and (time.time() - read_all_start_time) > timeout:
                    break
        return data
