# Copyright 2024 OpenC3, Inc.
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

import queue
from threading import Thread
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from openc3.interfaces.interface import Interface
from openc3.accessors.http_accessor import HttpAccessor
from openc3.packets.packet import Packet
from openc3.system.system import System
from openc3.utilities.logger import Logger


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.handle_request()

    def do_GET(self):
        self.handle_request()

    def handle_request(self):
        base = self.path.split("?")[0]
        if self.server.lookup.get(base):
            packets = self.server.lookup[base]
            status = 200

            for packet in packets:
                # Build the Response
                try:
                    status = int(packet.read("HTTP_STATUS"))
                except Exception:
                    # No HTTP_STATUS - Leave at default
                    pass

                self.send_response(status)

                # http_accessor stores all the pseudo-derived HTTP configuration in extra
                if packet.extra:
                    headers = packet.extra.get("HTTP_HEADERS")
                    if headers:
                        for key, value in headers:
                            self.send_header(key, value)
                self.end_headers()

                self.wfile.write(packet.buffer)

                # Save the Request
                packet_name = None
                try:
                    packet_name = packet.read("HTTP_PACKET")
                except Exception:
                    # No packet name means don't save the request as telemetry
                    pass
                if packet_name:
                    data = b""
                    if self.headers.get("content-length") and self.rfile:
                        length = int(self.headers.get("content-length"))
                        data = self.rfile.read(length)
                    extra = {}
                    extra["HTTP_REQUEST_TARGET_NAME"] = packet.target_name
                    extra["HTTP_REQUEST_PACKET_NAME"] = packet_name

                    if self.headers:
                        extra["HTTP_HEADERS"] = {}
                        for key, value in self.headers.items():
                            extra["HTTP_HEADERS"][key.lower()] = value

                    queries = {}
                    if "?" in self.path:
                        query_string = self.path.split("?", 1)[1]
                        for query in query_string.split("&"):
                            key, value = query.split("=", 1)
                            queries[key] = value

                    if len(queries) > 0:
                        extra["HTTP_QUERIES"] = {}
                        for key, value in queries.items():
                            extra["HTTP_QUERIES"][key] = value

                    self.server.request_queue.put((data, extra))


class HttpServerInterface(Interface):
    # @param port [Integer] HTTP port
    def __init__(self, port=80):
        super().__init__()
        self.listen_address = "0.0.0.0"  # Default to ANY
        self.port = int(port)
        self.server = None

    def build_path_lookup(self):
        self.lookup = {}
        for target_name in self.target_names:
            for packet_name, packet in System.commands.packets(target_name).items():
                packet.restore_defaults()
                path = None
                try:
                    path = packet.read("HTTP_PATH")
                except Exception as error:
                    # No HTTP_PATH is an error
                    Logger.error(
                        f"HttpServerInterface Packet {target_name} {packet_name} unable to read HTTP_PATH\n{repr(error)}"
                    )
                if path:
                    self.lookup[path] = self.lookup.get(path) or []
                    self.lookup[path].append(packet)

    # Supported Options
    # LISTEN_ADDRESS - Ip address of the interface to accept connections on
    # (see Interface#set_option)
    def set_option(self, option_name, option_values):
        super().set_option(option_name, option_values)
        if option_name.upper() == "LISTEN_ADDRESS":
            self.listen_address = option_values[0]

    def connection_string(self):
        return f"listening on {self.listen_address}:{self.port}"

    # Connects the interface to its target(s)
    def connect(self):
        # Can't build the lookup until after init because the target_names are not set
        self.build_path_lookup()
        self.server = ThreadingHTTPServer((self.listen_address, self.port), Handler)
        self.server.request_queue = queue.Queue()
        self.server.lookup = self.lookup
        self.server_thread = Thread(target=self.server.serve_forever)
        self.server_thread.start()
        super().connect()

    def connected(self):
        if self.server:
            return True
        else:
            return False

    # Disconnects the interface from its target(s)
    def disconnect(self):
        if self.server:
            self.server.shutdown()
            self.server_thread.join()
        self.server = None
        super().disconnect()

    def convert_packet_to_data(self, packet):
        raise RuntimeError("Commands cannot be sent to HttpServerInterface")

    def write_interface(self, data, extra=None):
        raise RuntimeError("Commands cannot be sent to HttpServerInterface")

    def read_interface(self):
        data, extra = self.server.request_queue.get(block=True)
        if data is None:
            return data, extra
        self.read_interface_base(data, extra)
        return data, extra

    # Called to convert the read data into a OpenC3 Packet object
    #
    # @param data [String] Raw packet data
    # @return [Packet] OpenC3 Packet with buffer filled with data
    def convert_data_to_packet(self, data, extra=None):
        packet = Packet(None, None, "BIG_ENDIAN", None, data)
        packet.accessor = HttpAccessor(packet)
        if extra:
            # Identify the response
            request_target_name = extra["HTTP_REQUEST_TARGET_NAME"]
            request_packet_name = extra["HTTP_REQUEST_PACKET_NAME"]
            if request_target_name and request_packet_name:
                packet.target_name = str(request_target_name).upper()
                packet.packet_name = str(request_packet_name).upper()
            extra.pop("HTTP_REQUEST_TARGET_NAME", None)
            extra.pop("HTTP_REQUEST_PACKET_NAME", None)
            packet.extra = extra

        return packet
