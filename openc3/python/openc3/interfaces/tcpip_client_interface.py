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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.interfaces.stream_interface import StreamInterface
from openc3.streams.tcpip_client_stream import TcpipClientStream
from openc3.config.config_parser import ConfigParser


# Base class for interfaces that act as a TCP/IP client
class TcpipClientInterface(StreamInterface):
    # self.param hostname [String] Machine to connect to
    # self.param write_port [Integer] Port to write commands to
    # self.param read_port [Integer] Port to read telemetry from
    # self.param write_timeout [Float] Seconds to wait before aborting writes
    # self.param read_timeout [Float|None] Seconds to wait before aborting reads.
    #   Pass None to block until the read is complete.
    # self.param protocol_type [String] Name of the protocol to use
    #   with this interface
    # self.param protocol_args [Array<String>] Arguments to pass to the protocol
    def __init__(
        self,
        hostname,
        write_port,
        read_port,
        write_timeout,
        read_timeout,
        protocol_type=None,
        *protocol_args
    ):
        super().__init__(protocol_type, protocol_args)
        self.hostname = hostname
        self.write_port = ConfigParser.handle_none(write_port)
        self.read_port = ConfigParser.handle_none(read_port)
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        if not self.read_port:
            self.read_allowed = False
        if not self.write_port:
            self.write_allowed = False
        if not self.write_port:
            self.write_raw_allowed = False

    # Connects the {TcpipClientStream} by passing the
    # initialization parameters to the {TcpipClientStream}.
    def connect(self):
        self.stream = TcpipClientStream(
            self.hostname,
            self.write_port,
            self.read_port,
            self.write_timeout,
            self.read_timeout,
        )
        super().connect()
