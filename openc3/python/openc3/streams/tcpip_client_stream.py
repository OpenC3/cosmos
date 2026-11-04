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

import errno
import os
import select
import socket

from openc3.config.config_parser import ConfigParser
from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.top_level import close_socket


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
        if self.connect_timeout is not None:
            self.connect_timeout = float(connect_timeout)

        super().__init__(write_socket, read_socket, write_timeout, read_timeout)

    # Connect the socket(s)
    def connect(self):
        try:
            if self.write_socket:
                self._connect(self.write_socket, self.hostname, self.write_port)
            if self.read_socket and self.read_socket != self.write_socket:
                self._connect(self.read_socket, self.hostname, self.read_port)
        except Exception:
            close_socket(self.write_socket)
            close_socket(self.read_socket)
            raise
        super().connect()

    def _connect(self, sock, hostname, port):
        # The sockets are non-blocking so connect_ex returns immediately. Wait for
        # the socket to become writable (3-way handshake done or failed) and then
        # read SO_ERROR to learn the outcome. Retrying connect() instead is not
        # portable: on macOS a retry while the handshake is still pending returns
        # EALREADY, which would wrongly be treated as connected.
        try:
            result = sock.connect_ex((hostname, port))
            if result in (errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EALREADY):
                # Windows reports a failed connect through the exceptional set
                _, writeable, exceptional = select.select([], [sock], [sock], self.connect_timeout)
                if not writeable and not exceptional:
                    raise TimeoutError(f"Connect timeout to {hostname}:{port}")
                result = sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
        except (ValueError, OSError) as error:
            # Python sets fileno() to -1 once a socket is closed, so a disconnect
            # from another thread surfaces as ValueError, EBADF or ENOTSOCK
            if isinstance(error, ValueError) or error.errno in (errno.EBADF, errno.ENOTSOCK):
                raise RuntimeError("Connect canceled") from error
            raise
        if result not in (0, errno.EISCONN):
            # OSError maps the errno to its subclass, e.g. ConnectionRefusedError
            raise OSError(result, os.strerror(result))
