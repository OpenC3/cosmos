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

import socket
import errno
from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.config.config_parser import ConfigParser


# Data {Stream} which reads and writes to TCPIP sockets. This class creates
# the actual sockets based on the constructor parameters. The rest of the
# interface is implemented by the super class {TcpipSocketStream}.
class TcpipClientStream(TcpipSocketStream):
    # self.param hostname [String] The host to connect to
    # self.param write_port [Integer|None] The port to write. Pass None to make this
    #   a read only stream.
    # self.param read_port [Integer|None] The port to read. Pass None to make this
    #   a write only stream.
    # self.param write_timeout [Float] Seconds to wait before aborting writes
    # self.param read_timeout [Float|None] Seconds to wait before aborting reads.
    #   Pass None to block until the read is complete.
    # self.param connect_timeout [Float|None] Seconds to wait before aborting connect.
    #   Pass None to block until the connection is complete.
    def __init__(
        self,
        hostname,
        write_port,
        read_port,
        write_timeout,
        read_timeout,
        connect_timeout=5.0,
    ):
        try:
            socket.gethostbyname(hostname)
        except socket.gaierror as error:
            raise RuntimeError(f"Invalid hostname {hostname}") from error
        self.hostname = hostname
        if str(hostname).upper() == "LOCALHOST":
            self.hostname = "127.0.0.1"
        self.write_port = ConfigParser.handle_none(write_port)
        if self.write_port:
            self.write_port = int(write_port)
        self.read_port = ConfigParser.handle_none(read_port)
        if self.read_port:
            self.read_port = int(read_port)

        write_socket = None
        if self.write_port:
            write_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
            write_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            write_socket.setblocking(False)
        read_socket = None
        if self.read_port:
            if self.write_port != self.read_port:
                read_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
                read_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                read_socket.setblocking(False)
            else:
                read_socket = write_socket

        self.connect_timeout = ConfigParser.handle_none(connect_timeout)
        if self.connect_timeout:
            self.connect_timeout = float(connect_timeout)

        super().__init__(write_socket, read_socket, write_timeout, read_timeout)

    # Connect the socket(s)
    def connect(self):
        if self.write_socket:
            self._connect(self.write_socket, self.hostname, self.write_port)
        if self.read_socket and self.read_socket != self.write_socket:
            self._connect(self.read_socket, self.hostname, self.read_port)
        super().connect()

    def _connect(self, socket, hostname, port):
        while True:
            try:
                socket.connect((hostname, port))
            except BlockingIOError:
                # select.select([], [socket], [], self.connect_timeout)
                # This is not an error condition
                continue
            except OSError as error:
                if error.errno == errno.EINPROGRESS:
                    continue
                if error.errno == errno.EISCONN or error.errno == errno.EALREADY:
                    break
                else:
                    raise error

    # except:
    #   try:
    #     _, sockets, _ = IO.select(None, [socket], None, self.connect_timeout) # wait 3-way handshake completion
    #   except IOError, Errno='ENOTSOCK':
    #     raise "Connect canceled"
    #   if sockets and !sockets.empty?:
    #     try:
    #       socket.connect_nonblock(addr) # check connection failure
    #     except IOError, Errno='ENOTSOCK':
    #       raise "Connect canceled"
    #     except Errno='EINPROGRESS':
    #       retry
    #     except Errno='EISCONN', Errno='EALREADY':
    #   else:
    #     raise "Connect timeout"
    # except IOError, Errno='ENOTSOCK':
    #   raise "Connect canceled"
