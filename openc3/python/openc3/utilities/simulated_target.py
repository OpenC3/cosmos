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

from openc3.system.system import System


# Base class for all virtual OpenC3 targets which must be implemented by
# a subclass. Provides a framework and helper methods to implement a
# virtual target which can cycle telemetry values and emit telemetry
# packets.
class SimulatedTarget:
    def __init__(self, target_name):
        self.tlm_packets = {}

        # Generate copy of telemetry packets for this target
        for name, packet in System.telemetry.packets(target_name).items():
            self.tlm_packets[name] = packet.clone()

        # Set defaults, template, and id values
        for name, packet in self.tlm_packets.items():
            packet.restore_defaults()
            setattr(packet, "packet_rate", 0)
            for item in packet.id_items:
                packet.write_item(item, item.id_value)

        self.current_cycle_delta = {}

    def set_rates(self):
        raise RuntimeError("Error: set_rates must be implemented by subclass")

    def write(self, packet):
        raise RuntimeError("Error: write must be implemented by subclass")

    def read(self, count_100hz, time):
        return self.get_pending_packets(count_100hz)

    def tick_period_seconds(self):
        return 0.01  # Override this method to optimize

    def tick_increment(self):
        return 1  # Override this method to optimize

    def set_rate(self, packet_name, rate):
        packet = self.tlm_packets[packet_name.upper()]
        if packet is not None:
            packet.packet_rate = rate

    def get_pending_packets(self, count_100hz):
        pending_packets = []

        # Determine if packets are due to be sent and add to pending
        for name, packet in self.tlm_packets.items():
            if packet.packet_rate > 0:
                if (count_100hz % packet.packet_rate) == 0:
                    pending_packets.append(packet)

        return pending_packets

    def cycle_tlm_item(self, packet, item_name, min, max, first_delta):
        packet_name = packet.packet_name
        if self.current_cycle_delta.get(packet_name) is None:
            self.current_cycle_delta[packet_name] = {}
        if self.current_cycle_delta[packet_name].get(item_name) is None:
            self.current_cycle_delta[packet_name][item_name] = first_delta

        current_delta = self.current_cycle_delta[packet_name][item_name]
        current_value = packet.read(item_name)
        updated_value = current_value + current_delta
        if updated_value < min:
            updated_value = min
            self.current_cycle_delta[packet_name][item_name] = -current_delta
        elif updated_value > max:
            updated_value = max
            self.current_cycle_delta[packet_name][item_name] = -current_delta
        packet.write(item_name, updated_value)
        return updated_value
