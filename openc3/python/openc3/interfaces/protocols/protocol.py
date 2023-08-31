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


from openc3.api import *
from openc3.config.config_parser import ConfigParser


# Base class for all OpenC3 protocols which defines a framework which must be
# implemented by a subclass.
class Protocol:
    # self.param allow_empty_data [True/False/None] Whether or not this protocol will allow an empty string
    # to be passed down to later Protocols (instead of returning 'STOP'). Can be True, False, or None, where
    # None is interpreted as True if not the Protocol is the last Protocol of the chain.
    def __init__(self, allow_empty_data=None):
        self.interface = None
        self.allow_empty_data = ConfigParser.handle_true_false_none(allow_empty_data)
        self.reset()

    def reset(self):
        pass

    def connect_reset(self):
        self.reset()

    def disconnect_reset(self):
        self.reset()

    # Ensure we have some data in match this is the only protocol:
    def read_data(self, data, extra=None):
        if len(data) <= 0:
            if self.allow_empty_data is None:
                if self.interface and self.interface.read_protocols[-1] == self:
                    # Last read interface in chain with auto self.allow_empty_data
                    return ("STOP", extra)
            elif self.allow_empty_data:
                # Don't self.allow_empty_data means STOP
                return ("STOP", extra)
        return (data, extra)

    def read_packet(self, packet):
        return packet

    def write_packet(self, packet):
        return packet

    def write_data(self, data, extra=None):
        return (data, extra)

    def post_write_interface(self, packet, data, extra=None):
        return (packet, data, extra)

    def protocol_cmd(self, cmd_name, *cmd_args):
        # Default do nothing - Implemented by subclasses
        return False
