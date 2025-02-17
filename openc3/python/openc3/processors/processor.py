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

import copy
from openc3.packets.packet import Packet


class Processor:
    # Create a new Processor
    # self.param value_type [Symbol or String] the value type to process
    def __init__(self, value_type="CONVERTED"):
        self.name = self.__class__.__name__.upper()
        value_type = value_type.upper()
        self.value_type = value_type
        if self.value_type not in Packet.VALUE_TYPES:
            raise ValueError(f"value_type must be RAW, CONVERTED, FORMATTED, or WITH_UNITS. Is {self.value_type}")

        self.results = {}

    @property
    def name(self):
        return self.__name

    @name.setter
    def name(self, name):
        self.__name = name.upper()

    # Perform processing on the packet.
    #
    # self.param packet [Packet] The packet which contains the value. This can
    #   be useful to reach into the packet and use other values in the
    #   conversion.
    # self.param buffer [String] The packet buffer
    # self.return The processed result
    def call(self, packet, buffer):
        raise RuntimeError("call method must be defined by subclass")

    def __str__(self):
        return self.__class__.__name__

    # Reset any state
    def reset(self):
        pass
        # By default do nothing

    # Make a light weight clone of this processor. This only creates a new hash of results
    #
    # self.return [Processor] A copy of the processor with a new hash of results
    def clone(self):
        return copy.deepcopy(self)

    # Convert to configuration file string
    def to_config(self):
        return f"  PROCESSOR {self.name} {self.__class__.__name__} {self.value_type}\n"

    def as_json(self):
        return {
            "name": self.name,
            "class": self.__class__.__name__,
            "params": [self.value_type],
        }
