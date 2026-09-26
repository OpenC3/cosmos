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

from openc3.config.config_parser import ConfigParser
from openc3.top_level import get_class_from_module
from openc3.utilities.logger import Logger
from openc3.utilities.read_queue import ReadQueue
from openc3.utilities.string import class_name_to_filename


# Base class for interfaces that act read and write from a stream
class StreamInterface(ReadQueue):
    def __init__(self, protocol_type=None, protocol_args=None):
        if protocol_args is None:
            protocol_args = []
        super().__init__()
        self.initialize_read_queue()
        self._stream = None
        self.protocol_type = ConfigParser.handle_none(protocol_type)
        self.protocol_args = protocol_args
        if self.protocol_type:
            protocol_class_name = str(protocol_type).capitalize() + "Protocol"
            filename = class_name_to_filename(protocol_class_name)
            klass = get_class_from_module(f"openc3.interfaces.protocols.{filename}", protocol_class_name)
            self.add_protocol(klass, protocol_args, "PARAMS")

    @property
    def stream(self):
        return self._stream

    # Replacing the stream stops the read thread which is reading the old one
    @stream.setter
    def stream(self, stream):
        self.stop_read_queue_thread()
        self._stream = stream

    def connect(self):
        super().connect()  # Reset the protocols
        if self.stream:
            self.stream.connect()
        # The read thread continuously drains the stream so the operating system
        # buffers don't fill up while we're busy processing the previous read
        if self.stream and self.read_allowed:
            self.start_read_queue_thread()

    def connected(self):
        if self.stream:
            return self.stream.connected()
        else:
            return False

    def disconnect(self):
        # Disconnect the stream first to unblock the read thread
        if self.stream:
            self.stream.disconnect()
        self.stop_read_queue_thread()
        super().disconnect()

    # Called by the read thread to perform a single blocking stream read
    # @return [bytes, None] Data read or None if the stream is done
    def read_queue_data(self):
        try:
            data = self.stream.read()
        except TimeoutError:
            Logger.error(f"{self.name}: Timeout waiting for data to be read")
            return None
        if data is None:
            Logger.info(f"{self.name}: {self.stream.__class__.__name__} read returned None")
            return None
        if len(data) <= 0:
            Logger.info(f"{self.name}: {self.stream.__class__.__name__} read returned 0 bytes (stream closed)")
            return None
        return data

    def read_interface(self):
        data = self.read_queue_pop()
        if data is None:
            return None, None

        extra = None
        self.read_interface_base(data, extra)
        return data, extra

    def write_interface(self, data, extra=None):
        self.write_interface_base(data, extra)
        self.stream.write(data)
        return data, extra
