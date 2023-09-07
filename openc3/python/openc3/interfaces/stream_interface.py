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

from openc3.interfaces.interface import Interface
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.utilities.string import class_name_to_filename
from openc3.top_level import get_class_from_module


# Base class for interfaces that act read and write from a stream
class StreamInterface(Interface):
    def __init__(self, protocol_type=None, protocol_args=[]):
        super().__init__()
        self.stream = None
        self.protocol_type = ConfigParser.handle_none(protocol_type)
        self.protocol_args = protocol_args
        if self.protocol_type:
            protocol_class_name = str(protocol_type).capitalize() + "Protocol"
            filename = class_name_to_filename(protocol_class_name)
            klass = get_class_from_module(
                f"openc3.interfaces.protocols.{filename}", protocol_class_name
            )
            self.add_protocol(klass, protocol_args, "PARAMS")

    def connect(self):
        super().connect()
        if self.stream:
            self.stream.connect()

    def connected(self):
        if self.stream:
            return self.stream.connected
        else:
            return False

    def disconnect(self):
        if self.stream:
            self.stream.disconnect()
        super().disconnect()

    def read_interface(self):
        timeout = False
        try:
            data = self.stream.read()
        except TimeoutError:
            Logger.error(f"{self.name}: Timeout waiting for data to be read")
            timeout = True
            data = None
        if data is None or len(data) <= 0:
            if data is None and not timeout:
                Logger.info(
                    f"{self.name}: {self.stream.__class__.__name__} read returned None"
                )
            if data is not None and len(data) <= 0:
                Logger.info(
                    f"{self.name}: {self.stream.__class__.__name__} read returned 0 bytes (stream closed)"
                )
            return (None, None)

        extra = None
        self.read_interface_base(data, extra)
        return (data, extra)

    def write_interface(self, data, extra=None):
        self.write_interface_base(data, extra)
        self.stream.write(data)
        return (data, extra)
