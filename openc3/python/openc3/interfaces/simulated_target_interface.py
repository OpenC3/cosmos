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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
from openc3.interfaces.interface import Interface
from openc3.utilities.logger import Logger
from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_module, filename_to_class_name


# An interface class that provides simulated telemetry and command responses
class SimulatedTargetInterface(Interface):
    # @param sim_target_file [String] Filename of the simulator target class
    def __init__(self, sim_target_file):
        super().__init__()
        self.__connected = False
        self.initialized = False
        self.count_100hz = 0
        self.next_tick_time = None
        self.pending_packets = []
        self.sim_target_class = get_class_from_module(
            filename_to_module(sim_target_file),
            filename_to_class_name(sim_target_file),
        )
        self.sim_target = None
        self.write_raw_allowed = False

    def connection_string(self):
        return self.sim_target_class.__name__

    # Initialize the simulated target object and "connect" to the target
    def connect(self):
        if not self.initialized:
            # Create Simulated Target Object
            self.sim_target = self.sim_target_class(self.target_names[0])
            # Set telemetry rates
            self.sim_target.set_rates()

            self.initialized = True

        self.count_100hz = 0

        # Save the current time + delta as the next expected tick time
        self.next_tick_time = time.time() + self.sim_target.tick_period_seconds()

        super().connect()
        self.__connected = True

    # @return [Boolean] Whether the simulated target is connected (initialized)
    def connected(self):
        return self.__connected

    # @return [Packet] Returns a simulated target packet from the simulator
    def read(self):
        packet = None
        if self.connected():
            while True:
                packet = self.first_pending_packet()
                if packet is None:
                    break
                # Support read_packet (but not read data) in protocols
                # Generic protocol use is not supported
                for protocol in self.read_protocols:
                    packet = protocol.read_packet(packet)
                    if packet == "DISCONNECT":
                        Logger.info(
                            f"{self.name}: Protocol {protocol.__class__.__name__} read_packet requested disconnect"
                        )
                        return None
                    if packet == "STOP":
                        break
                if packet != "STOP":
                    return packet

            while True:
                # Calculate time to sleep to make ticks the right distance apart
                now = time.time()
                delta = self.next_tick_time - now
                if delta > 0.0:
                    time.sleep(delta)  # Sleep between packets
                    if not self.connected():
                        return None
                elif delta < -1.0:
                    # Fell way behind - jump next tick time
                    self.next_tick_time = time.time()

                self.pending_packets = self.sim_target.read(self.count_100hz, self.next_tick_time)
                self.next_tick_time += self.sim_target.tick_period_seconds()
                self.count_100hz += self.sim_target.tick_increment()

                packet = self.first_pending_packet()
                if packet:
                    # Support read_packet (but not read data) in protocols
                    # Generic protocol use is not supported
                    for protocol in self.read_protocols:
                        packet = protocol.read_packet(packet)
                        if packet == "DISCONNECT":
                            Logger.info(
                                f"{self.name}: Protocol {protocol.__class__.__name__} read_packet requested disconnect"
                            )
                            return None
                        if packet == "STOP":
                            break
                    if packet == "STOP":
                        continue
                    return packet

        else:
            raise RuntimeError("Interface not connected")

    # @param packet [Packet] Command packet to send to the simulator
    def write(self, packet):
        if self.connected():
            # Update count of commands sent through this interface
            self.write_count += 1
            self.bytes_written += len(packet.buffer)
            self.written_raw_data_time = time.time()
            self.written_raw_data = packet.buffer

            # Have simulated target handle the packet
            self.sim_target.write(packet)
        else:
            raise RuntimeError("Interface not connected")

    # write_raw is not implemented and will raise a RuntimeError
    def write_raw(self, data):
        raise RuntimeError("write_raw not implemented for SimulatedTargetInterface")

    # Disconnect from the simulator
    def disconnect(self):
        self.__connected = False
        super().disconnect()

    def first_pending_packet(self):
        packet = None
        if len(self.pending_packets) != 0:
            self.read_count += 1
            packet = self.pending_packets.pop(0).clone()
            self.bytes_read += len(packet.buffer)
            self.read_raw_data_time = time.time()
            self.read_raw_data = packet.buffer
        return packet
