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

import time

from openc3.processors.processor import Processor


# Processor which sleeps while the decom microservice processes the packet.
# This simulates a decom microservice falling behind so events pile up in the
# streams it reads. Only used on the DECOM_STALL packet, which the target never
# sends, so it only runs when the packet is injected with inject_tlm.
# See procedures/limits_resync.py
class DecomStallProcessor(Processor):
    MAX_SECONDS = 300

    # @param item_name [String] Name of the item holding the seconds to stall
    # @param value_type #See Processor::initialize
    def __init__(self, item_name, value_type="CONVERTED"):
        super().__init__(value_type)
        self.item_name = str(item_name).upper()

    # See Processor#call
    def call(self, packet, buffer):
        seconds = float(packet.read(self.item_name, self.value_type, buffer))
        if seconds > 0:
            time.sleep(min(seconds, self.MAX_SECONDS))

    # Convert to configuration file string
    def to_config(self):
        return f"  PROCESSOR {self.name} {self.__class__.__name__} {self.item_name} {self.value_type}\n"

    def as_json(self):
        return {
            "name": self.name,
            "class": self.__class__.__name__,
            "params": [self.item_name, self.value_type],
        }
