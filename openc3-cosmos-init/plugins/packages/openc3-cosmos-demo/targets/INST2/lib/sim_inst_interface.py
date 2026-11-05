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
from openc3.interfaces.simulated_target_interface import SimulatedTargetInterface


class SimInstInterface(SimulatedTargetInterface):
    """Thin wrapper around SimulatedTargetInterface that optionally marks all
    telemetry packets as stored.  This is used by the INST2 demo target to
    exercise the STORED_LIMITS_MODE feature.

    Extra constructor parameter (all others forwarded to super):
        stored  - "true" or "false" (default "false").  When true every
                  packet returned by read() will have its stored flag set.
    """

    def __init__(self, sim_target_file, stored="false"):
        super().__init__(sim_target_file)
        self.mark_stored = ConfigParser.handle_true_false(stored)

    def first_pending_packet(self):
        packet = super().first_pending_packet()
        if packet and self.mark_stored:
            packet.stored = True
        return packet
