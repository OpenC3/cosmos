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

# Provides a demonstration of accessors

from openc3.utilities.simulated_target import SimulatedTarget


class SimAccess(SimulatedTarget):
    def set_rates(self):
        self.set_rate("JSONTLM", 100)
        self.set_rate("CBORTLM", 100)
        self.set_rate("XMLTLM", 100)
        self.set_rate("HTMLTLM", 100)

    def tick_period_seconds(self):
        return 1  # Override this method to optimize

    def tick_increment(self):
        return 100  # Override this method to optimize

    def write(self, packet):
        name = packet.packet_name.upper()

        json_packet = self.tlm_packets["JSONTLM"]
        cbor_packet = self.tlm_packets["CBORTLM"]
        xml_packet = self.tlm_packets["XMLTLM"]
        html_packet = self.tlm_packets["HTMLTLM"]

        match name:
            case "JSONCMD":
                json_packet.buffer = packet.buffer
            case "CBORCMD":
                cbor_packet.buffer = packet.buffer
            case "XMLCMD":
                xml_packet.buffer = packet.buffer
            case "HTMLCMD":
                html_packet.buffer = packet.buffer
