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

import os
import time
import base64
import random
import threading
from io import StringIO
from openc3.utilities.simulated_target import SimulatedTarget
from openc3.packets.structure import Structure
from openc3.packets.packet import Packet
from openc3.system.system import System
from openc3.top_level import kill_thread


# Simulated instrument for the demo. Populates several packets and cycles
# the telemetry to simulate an active target.
class SimInst(SimulatedTarget):
    SOLAR_PANEL_DFLTS = [-179.0, 179.0, -179.0, 179.0, -95.0]

    def __init__(self, target_name):
        super().__init__(target_name)

        self.target = System.targets[target_name]
        position_filename = os.path.join(self.target.dir, "data", "position.bin")
        attitude_filename = os.path.join(self.target.dir, "data", "attitude.bin")
        position_data = None
        with open(position_filename, "rb") as f:
            position_data = f.read()
        attitude_data = None
        with open(attitude_filename, "rb") as f:
            attitude_data = f.read()
        self.position_file = StringIO(position_data)
        self.position_file_size = len(position_data)
        self.attitude_file = StringIO(attitude_data)
        self.attitude_file_size = len(attitude_data)
        self.position_file_bytes_read = 0
        self.attitude_file_bytes_read = 0

        with open(os.path.join(self.target.dir, "public", "spiral.jpg"), "rb") as f:
            data = f.read()
            self.image = base64.b64encode(data)

        self.pos_packet = Structure("BIG_ENDIAN")
        self.pos_packet.append_item("DAY", 16, "UINT")
        self.pos_packet.append_item("MSOD", 32, "UINT")
        self.pos_packet.append_item("USOMS", 16, "UINT")
        self.pos_packet.append_item("POSX", 32, "FLOAT")
        self.pos_packet.append_item("POSY", 32, "FLOAT")
        self.pos_packet.append_item("POSZ", 32, "FLOAT")
        self.pos_packet.append_item("SPARE1", 16, "UINT")
        self.pos_packet.append_item("SPARE2", 32, "UINT")
        self.pos_packet.append_item("SPARE3", 16, "UINT")
        self.pos_packet.append_item("VELX", 32, "FLOAT")
        self.pos_packet.append_item("VELY", 32, "FLOAT")
        self.pos_packet.append_item("VELZ", 32, "FLOAT")
        self.pos_packet.append_item("SPARE4", 32, "UINT")

        self.att_packet = Structure("BIG_ENDIAN")
        self.att_packet.append_item("DAY", 16, "UINT")
        self.att_packet.append_item("MSOD", 32, "UINT")
        self.att_packet.append_item("USOMS", 16, "UINT")
        self.att_packet.append_item("Q1", 32, "FLOAT")
        self.att_packet.append_item("Q2", 32, "FLOAT")
        self.att_packet.append_item("Q3", 32, "FLOAT")
        self.att_packet.append_item("Q4", 32, "FLOAT")
        self.att_packet.append_item("BIASX", 32, "FLOAT")
        self.att_packet.append_item("BIASY", 32, "FLOAT")
        self.att_packet.append_item("BIASZ", 32, "FLOAT")
        self.att_packet.append_item("SPARE", 32, "FLOAT")

        packet = self.tlm_packets["HEALTH_STATUS"]
        packet.CcsdsSeqFlags = "NOGROUP"
        packet.CcsdsLength = len(packet.buffer) - 7
        packet.temp1 = 50.0
        packet.temp2 = -20.0
        packet.temp3 = 85.0
        packet.temp4 = 0.0
        packet.duration = 10.0
        packet.collect_type = "NORMAL"

        packet = self.tlm_packets["ADCS"]
        packet.CcsdsSeqFlags = "NOGROUP"
        packet.CcsdsLength = len(packet.buffer) - 7

        packet = self.tlm_packets["PARAMS"]
        packet.CcsdsSeqFlags = "NOGROUP"
        packet.CcsdsLength = len(packet.buffer) - 7
        packet.value1 = 0
        packet.value2 = 1
        packet.value3 = 2
        packet.value4 = 1
        packet.value5 = 0

        packet = self.tlm_packets["IMAGE"]
        packet.CcsdsSeqFlags = "NOGROUP"
        packet.CcsdsLength = len(packet.buffer) - 7

        packet = self.tlm_packets["MECH"]
        packet.CcsdsSeqFlags = "NOGROUP"
        packet.CcsdsLength = len(packet.buffer) - 7

        self.solar_panel_positions = SimInst.SOLAR_PANEL_DFLTS[:]
        self.solar_panel_thread = None
        self.solar_panel_thread_cancel = False

        self.trackStars = list()
        self.trackStars[0] = 1237
        self.trackStars[1] = 1329
        self.trackStars[2] = 1333
        self.trackStars[3] = 1139
        self.trackStars[4] = 1161
        self.trackStars[5] = 682
        self.trackStars[6] = 717
        self.trackStars[7] = 814
        self.trackStars[8] = 583
        self.trackStars[9] = 622

        self.bad_temp2 = False
        self.last_temp2 = 0
        self.quiet = False
        self.time_offset = 0

    def set_rates(self):
        self.set_rate("ADCS", 10)
        self.set_rate("HEALTH_STATUS", 100)
        self.set_rate("PARAMS", 100)
        self.set_rate("IMAGE", 100)
        self.set_rate("MECH", 10)

    def tick_period_seconds(self):
        return 0.1  # Override this method to optimize

    def tick_increment(self):
        return 10  # Override this method to optimize

    def write(self, packet):
        name = packet.packet_name.upper()

        hs_packet = self.tlm_packets["HEALTH_STATUS"]
        params_packet = self.tlm_packets["PARAMS"]

        match name:
            case "COLLECT":
                hs_packet.collects += 1
                hs_packet.duration = packet.read("duration")
                hs_packet.collect_type = packet.read("type")
            case "CLEAR":
                hs_packet.collects = 0
            case "MEMLOAD":
                hs_packet.blocktest = packet.read("data")
            case "QUIET":
                if packet.read("state") == "TRUE":
                    self.quiet = True
                else:
                    self.quiet = False
            case "TIME_OFFSET":
                self.time_offset = packet.read("seconds")
            case "SETPARAMS":
                params_packet.value1 = packet.read("value1")
                params_packet.value2 = packet.read("value2")
                params_packet.value3 = packet.read("value3")
                params_packet.value4 = packet.read("value4")
                params_packet.value5 = packet.read("value5")
            case "ASCIICMD":
                hs_packet.asciicmd = packet.read("string")
            case "SLRPNLDEPLOY":
                if self.solar_panel_thread and self.solar_panel_thread.is_alive():
                    return
                self.solar_panel_thread = threading.Thread(
                    target=self.solar_panel_thread_method
                )
                self.solar_panel_thread.start()
            case "SLRPNLRESET":
                kill_thread(self, self.solar_panel_thread)
                self.solar_panel_positions = SimInst.SOLAR_PANEL_DFLTS[:]

    def solar_panel_thread_method(self):
        self.solar_panel_thread_cancel = False
        for i in reversed(self.solar_panel_positions):
            while (self.solar_panel_positions[i] > 0.1) or (
                self.solar_panel_positions[i] < -0.1
            ):
                if self.solar_panel_positions[i] > 3.0:
                    self.solar_panel_positions[i] -= 3.0
                elif self.solar_panel_positions[i] < -3.0:
                    self.solar_panel_positions[i] += 3.0
                else:
                    self.solar_panel_positions[i] = 0.0
                time.sleep(0.10)
                if self.solar_panel_thread_cancel:
                    break
            if self.solar_panel_thread_cancel:
                self.solar_panel_thread_cancel = False
                break

    def graceful_kill(self):
        self.solar_panel_thread_cancel = True

    def read(self, count_100hz, time):
        pending_packets = self.get_pending_packets(count_100hz)

        for packet in pending_packets:
            match packet.packet_name:
                case "ADCS":
                    # Read 44 Bytes for Position Data
                    pos_data = None
                    try:
                        pos_data = self.position_file.read(44)
                        self.position_file_bytes_read += 44
                    except OSError:
                        pass  # Do Nothing

                    if pos_data is None or len(pos_data) == 0:
                        # Assume end of file - close and reopen
                        self.position_file.rewind
                        pos_data = self.position_file.read(44)
                        self.position_file_bytes_read = 44

                    self.pos_packet.buffer = pos_data
                    packet.posx = self.pos_packet.posx
                    packet.posy = self.pos_packet.posy
                    packet.posz = self.pos_packet.posz
                    packet.velx = self.pos_packet.velx
                    packet.vely = self.pos_packet.vely
                    packet.velz = self.pos_packet.velz

                    # Read 40 Bytes for Attitude Data
                    att_data = None
                    try:
                        att_data = self.attitude_file.read(40)
                        self.attitude_file_bytes_read += 40
                    except OSError:
                        pass  # Do Nothing

                    if att_data is None or len(att_data) == 0:
                        self.attitude_file.rewind
                        att_data = self.attitude_file.read(40)
                        self.attitude_file_bytes_read = 40

                    self.att_packet.buffer = att_data
                    packet.q1 = self.att_packet.q1
                    packet.q2 = self.att_packet.q2
                    packet.q3 = self.att_packet.q3
                    packet.q4 = self.att_packet.q4
                    packet.biasx = self.att_packet.biasx
                    packet.biasy = self.att_packet.biasy
                    packet.biasy = self.att_packet.biasz

                    packet.star1id = self.trackStars[((count_100hz / 100) + 0) % 10]
                    packet.star2id = self.trackStars[((count_100hz / 100) + 1) % 10]
                    packet.star3id = self.trackStars[((count_100hz / 100) + 2) % 10]
                    packet.star4id = self.trackStars[((count_100hz / 100) + 3) % 10]
                    packet.star5id = self.trackStars[((count_100hz / 100) + 4) % 10]

                    packet.posprogress = (
                        float(self.position_file_bytes_read)
                        / float(self.position_file_size)
                    ) * 100.0
                    packet.attprogress = (
                        float(self.attitude_file_bytes_read)
                        / float(self.attitude_file_size)
                    ) * 100.0

                    packet.timesec = time.tv_sec - self.time_offset
                    packet.timeus = time.tv_usec
                    packet.ccsdsseqcnt += 1

                case "HEALTH_STATUS":
                    if self.quiet:
                        self.bad_temp2 = False
                        self.cycle_tlm_item(packet, "temp1", -15.0, 15.0, 5.0)
                        self.cycle_tlm_item(packet, "temp2", -50.0, 25.0, -1.0)
                        self.cycle_tlm_item(packet, "temp3", 0.0, 50.0, 2.0)
                    else:
                        self.cycle_tlm_item(packet, "temp1", -95.0, 95.0, 5.0)
                        if self.bad_temp2:
                            packet.write("temp2", self.last_temp2)
                            self.bad_temp2 = False
                        self.last_temp2 = self.cycle_tlm_item(
                            packet, "temp2", -50.0, 50.0, -1.0
                        )
                        if (packet.temp2.abs - 30).abs < 2:
                            packet.write("temp2", float("nan"))
                            self.bad_temp2 = True
                        elif (packet.temp2.abs - 20).abs < 2:
                            packet.write("temp2", float("-inf"))
                            self.bad_temp2 = True
                        elif (packet.temp2.abs - 10).abs < 2:
                            packet.write("temp2", float("inf"))
                            self.bad_temp2 = True
                        self.cycle_tlm_item(packet, "temp3", -30.0, 80.0, 2.0)
                    self.cycle_tlm_item(packet, "temp4", 0.0, 20.0, -0.1)

                    packet.timesec = time.tv_sec - self.time_offset
                    packet.timeus = time.tv_usec
                    packet.ccsdsseqcnt += 1

                    ary = []
                    for index in range(0, 10):
                        ary.append(index)
                    packet.ary = ary

                    if self.quiet:
                        packet.ground1status = "CONNECTED"
                        packet.ground2status = "CONNECTED"
                    else:
                        if count_100hz % 1000 == 0:
                            if packet.ground1status == "CONNECTED":
                                packet.ground1status = "UNAVAILABLE"
                            else:
                                packet.ground1status = "CONNECTED"

                        if count_100hz % 500 == 0:
                            if packet.ground2status == "CONNECTED":
                                packet.ground2status = "UNAVAILABLE"
                            else:
                                packet.ground2status = "CONNECTED"

                case "PARAMS":
                    packet.timesec = time.tv_sec - self.time_offset
                    packet.timeus = time.tv_usec
                    packet.ccsdsseqcnt += 1

                case "IMAGE":
                    packet.timesec = time.tv_sec - self.time_offset
                    packet.timeus = time.tv_usec
                    packet.image = self.image
                    # Create an Array of random bytes
                    packet.block = random.randbytes(1000)
                    packet.ccsdsseqcnt += 1

                case "MECH":
                    packet.timesec = time.tv_sec - self.time_offset
                    packet.timeus = time.tv_usec
                    packet.ccsdsseqcnt += 1
                    packet.slrpnl1 = self.solar_panel_positions[0]
                    packet.slrpnl2 = self.solar_panel_positions[1]
                    packet.slrpnl3 = self.solar_panel_positions[2]
                    packet.slrpnl4 = self.solar_panel_positions[3]
                    packet.slrpnl5 = self.solar_panel_positions[4]
                    packet.current = 0.5

        # Every 10s throw an unknown packet at the server just to demo that
        if count_100hz % 1000 == 900:
            pending_packets.append(
                Packet(None, None, "BIG_ENDIAN", None, random.randbytes(10))
            )

        return pending_packets
