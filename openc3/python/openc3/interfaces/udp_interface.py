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

import socket
from openc3.io.udp_sockets import UdpReadSocket, UdpWriteSocket, UdpReadWriteSocket
from openc3.interfaces.interface import Interface
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.top_level import close_socket


# Base class for interfaces that send and receive messages over UDP
class UdpInterface(Interface):
    # @param hostname [String] Machine to connect to
    # @param write_dest_port [Integer] Port to write commands to
    # @param read_port [Integer] Port to read telemetry from
    # @param write_src_port [Integer] Port to allow replies if needed
    # @param interface_address [String] If the destination machine represented
    #   by hostname supports multicast, then interface_address is used to
    #   configure the outgoing multicast address.
    # @param ttl [Integer] Time To Live value. The number of intermediate
    #   routers allowed before dropping the packet.
    # @param write_timeout [Float] Seconds to wait before aborting writes
    # @param read_timeout [Float|nil] Seconds to wait before aborting reads.
    #   Pass nil to block until the read is complete.
    # @param bind_address [String] Address to bind UDP ports to
    def __init__(
        self,
        hostname,
        write_dest_port,
        read_port,
        write_src_port=None,
        interface_address=None,
        ttl=128,  # default for Windows
        write_timeout=10.0,
        read_timeout=None,
        bind_address="0.0.0.0",
    ):
        super().__init__()
        self.hostname = ConfigParser.handle_none(hostname)
        if self.hostname is not None:
            self.hostname = str(hostname)
            if self.hostname.upper() == "LOCALHOST":
                self.hostname = "127.0.0.1"
        self.write_dest_port = ConfigParser.handle_none(write_dest_port)
        if self.write_dest_port is not None:
            self.write_dest_port = int(write_dest_port)
        self.read_port = ConfigParser.handle_none(read_port)
        if self.read_port is not None:
            self.read_port = int(read_port)
        self.write_src_port = ConfigParser.handle_none(write_src_port)
        if self.write_src_port is not None:
            self.write_src_port = int(write_src_port)
        self.interface_address = ConfigParser.handle_none(interface_address)
        if self.interface_address and self.interface_address.upper() == "LOCALHOST":
            self.interface_address = "127.0.0.1"
        self.ttl = int(ttl)
        if self.ttl < 1:
            self.ttl = 1
        self.write_timeout = ConfigParser.handle_none(write_timeout)
        if self.write_timeout is not None:
            self.write_timeout = float(write_timeout)
        else:
            Logger.warn("Warning: To avoid interface lock, write_timeout can not be None. Setting to 10 seconds.")
            self.write_timeout = 10.0
        self.read_timeout = ConfigParser.handle_none(read_timeout)
        if self.read_timeout is not None:
            self.read_timeout = float(read_timeout)
        self.bind_address = ConfigParser.handle_none(bind_address)
        if self.bind_address and self.bind_address.upper() == "LOCALHOST":
            self.bind_address = "127.0.0.1"
        self.write_socket = None
        self.read_socket = None
        if self.read_port is None:
            self.read_allowed = False
        if self.write_dest_port is None:
            self.write_allowed = False
        if self.write_dest_port is None:
            self.write_raw_allowed = False

    def connection_string(self):
        result = ""
        if self.write_dest_port:
            result += f" {self.hostname}:{self.write_dest_port} (write dest port)"
        if self.write_src_port:
            result += f" {self.write_src_port} (write src port)"
        if self.read_port:
            result += f" {self.hostname}:{self.read_port} (read)"
        if self.interface_address:
            result += f" {self.interface_address} (interface addr)"
        if self.bind_address != "0.0.0.0":
            result += f" {self.bind_address} (bind addr)"
        return result.strip()

    # Creates a new {UdpWriteSocket} if the the write_dest_port was given in
    # the constructor and a new {UdpReadSocket} if the read_port was given in
    # the constructor.
    def connect(self):
        if self.read_port and self.write_dest_port and self.write_src_port and (self.read_port == self.write_src_port):
            self.read_socket = UdpReadWriteSocket(
                self.read_port,
                self.bind_address,
                self.write_dest_port,
                self.hostname,
                self.interface_address,
                self.ttl,
            )
            self.write_socket = self.read_socket
        else:
            if self.read_port:
                self.read_socket = UdpReadSocket(
                    self.read_port,
                    self.hostname,
                    self.interface_address,
                    self.bind_address,
                )
            if self.write_dest_port:
                self.write_socket = UdpWriteSocket(
                    self.hostname,
                    self.write_dest_port,
                    self.write_src_port,
                    self.interface_address,
                    self.ttl,
                    self.bind_address,
                )
        self.thread_sleeper = None
        super().connect()

    # @return [Boolean] Whether the active ports (read and/or write) have
    #   created sockets. Since UDP is connectionless, creation of the sockets
    #   is used to determine connection.
    def connected(self):
        if self.write_dest_port is not None and self.read_port is not None:
            if self.write_socket and self.read_socket:
                return True
            else:
                return False
        elif self.write_dest_port is not None:
            if self.write_socket:
                return True
            else:
                return False
        else:
            if self.read_socket:
                return True
            else:
                return False

    # Close the active ports (read and/or write) and set the sockets to nil.
    def disconnect(self):
        if self.write_socket != self.read_socket:
            close_socket(self.write_socket)
        close_socket(self.read_socket)
        self.write_socket = None
        self.read_socket = None
        if self.thread_sleeper:
            self.thread_sleeper.cancel()
        self.thread_sleeper = None
        super().disconnect()

    def read(self):
        if self.read_port:
            return super().read()

        # Write only interface so stop the thread which calls read
        self.thread_sleeper = Sleeper()
        while self.connected():
            self.thread_sleeper.sleep(1_000_000_000)
        return None

    # Reads from the socket if the read_port is defined
    def read_interface(self):
        try:
            data = self.read_socket.read(self.read_timeout)
            if len(data) <= 0:
                Logger.info(f"{self.name}: Udp read returned 0 bytes (stream closed)")
            extra = None
            self.read_interface_base(data, extra)
            return (data, extra)
        # TODO: select.select can throw TypeErorr: fileno() returned a non-integer
        # Does it also throw socket.error?
        except (TypeError, socket.error):
            return None, None

    # Writes to the socket
    # @param data [String] Raw packet data
    def write_interface(self, data, extra=None):
        self.write_interface_base(data, extra)
        self.write_socket.write(data, self.write_timeout)
        return data, extra
