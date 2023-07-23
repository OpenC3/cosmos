#!/usr/bin/env python3

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


from openc3.packets.packet import Packet


class PacketConfig:
    COMMAND = "Command"
    TELEMETRY = "Telemetry"

    def __init__(self):
        self.name = None
        self.telemetry = {}
        self.commands = {}
        self.limits_groups = {}
        self.limits_sets = ["DEFAULT"]
        # Hash of Hashes. First index by target name and then item name.
        # Returns an array of packets with that target and item.
        self.latest_data = {}
        self.warnings = []
        self.cmd_id_value_hash = {}
        self.tlm_id_value_hash = {}

        # Create unknown packets
        self.commands["UNKNOWN"] = {}
        self.commands["UNKNOWN"]["UNKNOWN"] = Packet("UNKNOWN", "UNKNOWN", "BIG_ENDIAN")
        self.telemetry["UNKNOWN"] = {}
        self.telemetry["UNKNOWN"]["UNKNOWN"] = Packet(
            "UNKNOWN", "UNKNOWN", "BIG_ENDIAN"
        )
