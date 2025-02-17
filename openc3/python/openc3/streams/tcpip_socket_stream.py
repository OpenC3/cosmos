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

import select
import socket
import threading
import multiprocessing
from openc3.streams.stream import Stream
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.top_level import close_socket


class TcpipSocketStream(Stream):
    # self.param write_socket [Socket] Socket to write
    # self.param read_socket [Socket] Socket to read
    # self.param write_timeout [Float] Seconds to wait before aborting writes
    # self.param read_timeout [Float|None] Seconds to wait before aborting reads.
    #   Pass None to block until the read is complete.
    def __init__(self, write_socket, read_socket, write_timeout, read_timeout):
        super().__init__()
        self.write_socket = write_socket
        self.read_socket = read_socket
        self.write_timeout = ConfigParser.handle_none(write_timeout)
        if self.write_timeout:
            self.write_timeout = float(write_timeout)
        else:
            Logger.warn("Warning: To avoid interface lock, write_timeout can not be None. Setting to 10 seconds.")
            self.write_timeout = 10.0
        self.read_timeout = ConfigParser.handle_none(read_timeout)
        if self.read_timeout:
            self.read_timeout = float(read_timeout)

        # Mutex on write is needed to protect from commands coming in from more
        # than one tool
        self.write_mutex = threading.Lock()
        self.pipe_reader, self.pipe_writer = multiprocessing.Pipe()
        self._connected = False

    # self.return [String] Returns a binary string of data from the socket
    def read(self):
        if not self.read_socket:
            raise RuntimeError("Attempt to read from write only stream")

        data = ""
        # No read mutex is needed because reads happen serially
        while True:  # Loop until we get some data
            try:
                data = self.read_socket.recv(4096, socket.MSG_DONTWAIT)
            # Non-blocking sockets return an errno EAGAIN or EWOULDBLOCK
            # if there is no data available
            except socket.error as error:
                if error.errno == socket.EAGAIN or error.errno == socket.EWOULDBLOCK:
                    # If select returns something it means the socket is now available for
                    # reading so retry the read. If it returns empty list it means we timed out.
                    # If the pipe is present that means we closed the socket
                    readable, _, _ = select.select(
                        [self.read_socket, self.pipe_reader],
                        [],
                        [],
                        self.read_timeout,
                    )
                    if readable and self.pipe_reader in readable:
                        data = ""
                    else:
                        continue
            break
        return data

    # self.param data [String] A binary string of data to write to the socket
    def write(self, data):
        if not self.write_socket:
            raise RuntimeError("Attempt to write to read only stream")

        with self.write_mutex:
            num_bytes_to_send = len(data)
            total_bytes_sent = 0
            bytes_sent = 0
            data_to_send = data

            while True:
                try:
                    bytes_sent = self.write_socket.send(data_to_send, socket.MSG_DONTWAIT)
                # Non-blocking sockets return an errno EAGAIN or EWOULDBLOCK
                # if the write would block
                except socket.error as error:
                    if error.errno == socket.EAGAIN or error.errno == socket.EWOULDBLOCK:
                        # Wait for the socket to be ready for writing or for the timeout
                        _, writeable, _ = select.select([], [self.write_socket], [], self.write_timeout)
                        # If select returns something it means the socket is now available for
                        # writing so retry the write. If it returns None it means we timed out.
                        if writeable:
                            continue
                        else:
                            raise RuntimeError("Write Timeout")
                total_bytes_sent += bytes_sent
                if total_bytes_sent >= num_bytes_to_send:
                    break

                data_to_send = data[total_bytes_sent:]

    # Connect the stream
    def connect(self):
        # If called directly this class is acting as a server and does not need to connect the sockets
        self._connected = True

    def connected(self):
        return self._connected

    # Disconnect by closing the sockets
    def disconnect(self):
        if not self._connected:
            return
        close_socket(self.write_socket)
        close_socket(self.read_socket)
        self.pipe_writer.send(".")
        self._connected = False
