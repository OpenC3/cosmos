# Copyright 2025 OpenC3, Inc.
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

from websockets.exceptions import ConnectionClosedOK
from websockets.sync.client import connect


class WebSocketClientStream:
    def __init__(self, url, write_timeout, read_timeout, connect_timeout=5.0):
        """
        Initialize WebSocketClientStream

        Args:
            url (str): The host to connect to
            write_timeout (float): Seconds to wait before aborting writes
            read_timeout (float|None): Seconds to wait before aborting reads. Pass None to block until the read is complete.
            connect_timeout (float|None): Seconds to wait before aborting connect. Pass None to block until the connection is complete.
        """
        self.url = url
        self.recv_timeout = read_timeout
        self.connect_timeout = connect_timeout
        self.headers = {}

    def connect(self):
        self.connection = connect(
            self.url,
            subprotocols=["actioncable-v1-json"],
            open_timeout=self.connect_timeout,
            additional_headers=self.headers,
        )
        return True

    def read(self):
        while True:
            try:
                return self.connection.recv(self.recv_timeout)
            except TimeoutError:
                return None
            except ConnectionClosedOK:
                # ConnectionClosedOK is raised when the server closes the connection in a normal way
                # This happens when the client has read all messages in the requested time range
                return None

    def write(self, data):
        self.connection.send(data)

    def connected(self):
        if self.connection:
            return True
        return False

    def disconnect(self):
        if self.connection:
            self.connection.close()
