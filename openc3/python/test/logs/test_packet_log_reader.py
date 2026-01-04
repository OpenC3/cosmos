# Copyright 2025 OpenC3, Inc.
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

"""
Tests for PacketLogReader.

These tests match the functionality of the Ruby spec at:
openc3/spec/logs/packet_log_reader_spec.rb
"""

import json
import os
import struct
import tempfile
import time
import unittest
from datetime import datetime, timezone

from openc3.logs.packet_log_reader import PacketLogReader
from openc3.logs.packet_log_writer import PacketLogWriter
from openc3.logs.packet_log_constants import (
    COSMOS2_FILE_HEADER,
    COSMOS4_FILE_HEADER,
    OPENC3_FILE_HEADER,
)
from openc3.packets.json_packet import JsonPacket

# 1 second in nanoseconds
NSEC_PER_SECOND = 1_000_000_000


class TestPacketLogReaderOpen(unittest.TestCase):
    """Tests for PacketLogReader.open()"""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        self.plr.close()
        # Clean up temp files
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def test_complains_if_log_file_too_small(self):
        """complains if the log file is too small"""
        path = os.path.join(self.temp_dir, "test.bin")
        with open(path, "wb") as f:
            f.write(b"BLAH")

        with self.assertRaises(ValueError) as context:
            self.plr.open(path)
        self.assertIn("Failed to read", str(context.exception))

    def test_complains_if_log_has_cosmos2_header(self):
        """complains if the log has a COSMOS2 header"""
        path = os.path.join(self.temp_dir, "test.bin")
        with open(path, "wb") as f:
            f.write(COSMOS2_FILE_HEADER + b"\x00\x00\x00\x00")

        with self.assertRaises(ValueError) as context:
            self.plr.open(path)
        self.assertEqual("COSMOS 2 log file must be converted to OpenC3 5", str(context.exception))

    def test_complains_if_log_has_cosmos4_header(self):
        """complains if the log has a COSMOS4 header"""
        path = os.path.join(self.temp_dir, "test.bin")
        with open(path, "wb") as f:
            f.write(COSMOS4_FILE_HEADER + b"\x00\x00\x00\x00")

        with self.assertRaises(ValueError) as context:
            self.plr.open(path)
        self.assertEqual("COSMOS 4 log file must be converted to OpenC3 5", str(context.exception))

    def test_complains_if_log_has_no_openc3_header(self):
        """complains if the log has no OpenC3 header"""
        path = os.path.join(self.temp_dir, "test.bin")
        with open(path, "wb") as f:
            f.write(b"\x00" * 20)

        with self.assertRaises(ValueError) as context:
            self.plr.open(path)
        self.assertEqual("OpenC3 file header not found", str(context.exception))


class TestPacketLogReaderWithJsonTelemetry(unittest.TestCase):
    """Tests for PacketLogReader.each() with JSON telemetry"""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()
        self.start_time = datetime.now(timezone.utc)
        self.start_nsec = int(self.start_time.timestamp() * 1_000_000_000)
        self.times = [
            self.start_nsec,
            self.start_nsec + NSEC_PER_SECOND,
            self.start_nsec + 2 * NSEC_PER_SECOND,
        ]
        self._setup_logfile("TLM", "JSON_PACKET")

    def tearDown(self):
        self.plr.close()
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _setup_logfile(self, cmd_or_tlm, raw_or_json):
        """Create a test log file with telemetry packets."""
        plw = PacketLogWriter(self.temp_dir, "spec")

        self.pkt_data = {"COLLECTS": 100, "TEMP1": 25.5, "CCSDSVER": 0}
        target_name = "INST"
        packet_name = "HEALTH_STATUS"

        if raw_or_json == "RAW_PACKET":
            data = b"\x00\x01\x02\x03\x04\x05\x06\x07"
        else:
            data = self.pkt_data

        for t in self.times:
            plw.write(raw_or_json, cmd_or_tlm, target_name, packet_name, t, True, data, None, "0-0")

        self.logfile = plw.filename
        plw.shutdown()

    def test_returns_identified_packets(self):
        """returns identified packets"""
        index = 0
        for packet in self.plr.each(self.logfile):
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.target_name, "INST")
            self.assertEqual(packet.packet_name, "HEALTH_STATUS")
            self.assertEqual(packet.read("COLLECTS"), 100)
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        self.assertEqual(index, 3)


class TestPacketLogReaderWithJsonCommands(unittest.TestCase):
    """Tests for PacketLogReader.each() with JSON commands"""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()
        self.start_time = datetime.now(timezone.utc)
        self.start_nsec = int(self.start_time.timestamp() * 1_000_000_000)
        self.times = [
            self.start_nsec,
            self.start_nsec + NSEC_PER_SECOND,
            self.start_nsec + 2 * NSEC_PER_SECOND,
        ]
        self._setup_logfile()

    def tearDown(self):
        self.plr.close()
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _setup_logfile(self):
        """Create a test log file with command packets."""
        plw = PacketLogWriter(self.temp_dir, "spec")

        self.pkt_data = {"DURATION": 10.0, "TYPE": "NORMAL"}
        target_name = "INST"
        packet_name = "COLLECT"

        for t in self.times:
            plw.write("JSON_PACKET", "CMD", target_name, packet_name, t, True, self.pkt_data, None, "0-0")

        self.logfile = plw.filename
        plw.shutdown()

    def test_returns_identified_packets(self):
        """returns identified packets"""
        index = 0
        for packet in self.plr.each(self.logfile):
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.target_name, "INST")
            self.assertEqual(packet.packet_name, "COLLECT")
            self.assertEqual(packet.cmd_or_tlm, "CMD")
            self.assertEqual(packet.read("DURATION"), 10.0)
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        self.assertEqual(index, 3)


class TestPacketLogReaderWithRawTelemetry(unittest.TestCase):
    """Tests for PacketLogReader.each() with raw telemetry"""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()
        self.start_time = datetime.now(timezone.utc)
        self.start_nsec = int(self.start_time.timestamp() * 1_000_000_000)
        self.times = [
            self.start_nsec,
            self.start_nsec + NSEC_PER_SECOND,
            self.start_nsec + 2 * NSEC_PER_SECOND,
        ]
        self._setup_logfile()

    def tearDown(self):
        self.plr.close()
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _setup_logfile(self):
        """Create a test log file with raw telemetry packets."""
        plw = PacketLogWriter(self.temp_dir, "spec")

        self.pkt_data = b"\x00\x01\x02\x03\x04\x05\x06\x07"
        target_name = "INST"
        packet_name = "HEALTH_STATUS"

        for t in self.times:
            plw.write("RAW_PACKET", "TLM", target_name, packet_name, t, True, self.pkt_data, None, "0-0")

        self.logfile = plw.filename
        plw.shutdown()

    def test_returns_packets(self):
        """returns raw packets"""
        index = 0
        for packet in self.plr.each(self.logfile, identify_and_define=False):
            self.assertEqual(packet.target_name, "INST")
            self.assertEqual(packet.packet_name, "HEALTH_STATUS")
            self.assertEqual(packet.cmd_or_tlm, "TLM")
            self.assertEqual(packet.buffer, self.pkt_data)
            index += 1
        self.assertEqual(index, 3)


class TestPacketLogReaderWithStartEndTimes(unittest.TestCase):
    """Tests for PacketLogReader.each() with start and end times"""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()
        self.start_time = datetime.now(timezone.utc)
        self.start_nsec = int(self.start_time.timestamp() * 1_000_000_000)
        self.times = [
            self.start_nsec,
            self.start_nsec + NSEC_PER_SECOND,
            self.start_nsec + 2 * NSEC_PER_SECOND,
        ]
        self._setup_logfile()

    def tearDown(self):
        self.plr.close()
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _setup_logfile(self):
        """Create a test log file."""
        plw = PacketLogWriter(self.temp_dir, "spec")

        pkt_data = {"COLLECTS": 100, "TEMP1": 25.5}
        target_name = "INST"
        packet_name = "HEALTH_STATUS"

        for t in self.times:
            plw.write("JSON_PACKET", "TLM", target_name, packet_name, t, True, pkt_data, None, "0-0")

        self.logfile = plw.filename
        plw.shutdown()

    def test_returns_all_packets_if_start_time_before_all(self):
        """returns all packets if the start time is before all"""
        start = datetime.fromtimestamp((self.start_nsec - NSEC_PER_SECOND) / 1e9, tz=timezone.utc)
        index = 0
        for packet in self.plr.each(self.logfile, start_time=start):
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        self.assertEqual(index, 3)

    def test_returns_no_packets_if_start_time_after_all(self):
        """returns no packets if the start time is after all"""
        start = datetime.fromtimestamp((self.start_nsec + 10 * NSEC_PER_SECOND) / 1e9, tz=timezone.utc)
        index = 0
        for packet in self.plr.each(self.logfile, start_time=start):
            index += 1
        self.assertEqual(index, 0)

    def test_returns_all_packets_after_start_time(self):
        """returns all packets after a start time"""
        # Start after first packet (use half second offset since datetime has only microsecond precision)
        start = datetime.fromtimestamp((self.start_nsec + NSEC_PER_SECOND // 2) / 1e9, tz=timezone.utc)
        index = 1  # Start at index 1
        for packet in self.plr.each(self.logfile, start_time=start):
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        self.assertEqual(index, 3)

    def test_returns_no_packets_if_end_time_before_all(self):
        """returns no packets if the end time is before all"""
        end = datetime.fromtimestamp((self.start_nsec - NSEC_PER_SECOND) / 1e9, tz=timezone.utc)
        index = 0
        for packet in self.plr.each(self.logfile, end_time=end):
            index += 1
        self.assertEqual(index, 0)

    def test_returns_all_packets_if_end_time_after_all(self):
        """returns all packets if the end time is after all"""
        end = datetime.fromtimestamp((self.start_nsec + 4 * NSEC_PER_SECOND) / 1e9, tz=timezone.utc)
        index = 0
        for packet in self.plr.each(self.logfile, end_time=end):
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        self.assertEqual(index, 3)

    def test_returns_all_packets_before_end_time(self):
        """returns all packets before an end time"""
        # End at second packet (exactly)
        end = datetime.fromtimestamp((self.start_nsec + NSEC_PER_SECOND) / 1e9, tz=timezone.utc)
        index = 0
        for packet in self.plr.each(self.logfile, end_time=end):
            self.assertEqual(packet.time_nsec, self.times[index])
            index += 1
        # Should get first two (packet at end_time is included)
        self.assertEqual(index, 2)


class TestPacketLogReaderProperties(unittest.TestCase):
    """Tests for PacketLogReader properties."""

    def setUp(self):
        self.plr = PacketLogReader()
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        self.plr.close()
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _create_logfile(self):
        """Create a simple test log file."""
        plw = PacketLogWriter(self.temp_dir, "spec")
        time_nsec = int(time.time() * 1e9)
        plw.write("JSON_PACKET", "TLM", "INST", "HEALTH_STATUS", time_nsec, True, {"VALUE": 1}, None, "0-0")
        plw.write("JSON_PACKET", "TLM", "INST", "HEALTH_STATUS", time_nsec + 1000, True, {"VALUE": 2}, None, "0-0")
        filename = plw.filename
        plw.shutdown()
        return filename

    def test_size_returns_file_size(self):
        """size property returns the file size"""
        path = self._create_logfile()
        self.plr.open(path)
        expected_size = os.path.getsize(path)
        self.assertEqual(self.plr.size, expected_size)

    def test_bytes_read_returns_current_position(self):
        """bytes_read property returns current file position"""
        path = self._create_logfile()
        self.plr.open(path)
        initial_pos = self.plr.bytes_read

        # Read first packet
        self.plr.read()
        after_first = self.plr.bytes_read

        # Should have advanced
        self.assertGreater(after_first, initial_pos)

    def test_filename_returns_opened_file(self):
        """filename property returns the opened filename"""
        path = self._create_logfile()
        self.plr.open(path)
        self.assertEqual(self.plr.filename, path)


class TestJsonPacket(unittest.TestCase):
    """Tests for JsonPacket class."""

    def test_read_returns_raw_value(self):
        """read returns raw value"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"COLLECTS": 100, "TEMP1": 25.5, "COLLECTS__C": "ONE HUNDRED"}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        self.assertEqual(packet.read("COLLECTS", "RAW"), 100)
        self.assertEqual(packet.read("TEMP1", "RAW"), 25.5)

    def test_read_returns_converted_value(self):
        """read returns converted value"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"COLLECTS": 100, "COLLECTS__C": "ONE HUNDRED", "TEMP1": 25.5}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        self.assertEqual(packet.read("COLLECTS", "CONVERTED"), "ONE HUNDRED")
        self.assertEqual(packet.read("TEMP1", "CONVERTED"), 25.5)  # Falls back to raw

    def test_read_returns_formatted_value(self):
        """read returns formatted value"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"COLLECTS": 100, "COLLECTS__F": "100 counts"}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        self.assertEqual(packet.read("COLLECTS", "FORMATTED"), "100 counts")

    def test_read_with_array_index(self):
        """read handles array index notation"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"ARRAY_ITEM": [1, 2, 3, 4, 5]}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        self.assertEqual(packet.read("ARRAY_ITEM[0]"), 1)
        self.assertEqual(packet.read("ARRAY_ITEM[2]"), 3)
        self.assertEqual(packet.read("ARRAY_ITEM[4]"), 5)

    def test_read_with_key_map(self):
        """read handles key map for decompression"""
        time_nsec = int(time.time() * 1e9)
        compressed_data = {"0": 100, "1": 25.5, "2": 0}
        key_map = {"0": "COLLECTS", "1": "TEMP1", "2": "CCSDSVER"}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, compressed_data, key_map)

        self.assertEqual(packet.read("COLLECTS"), 100)
        self.assertEqual(packet.read("TEMP1"), 25.5)
        self.assertEqual(packet.read("CCSDSVER"), 0)

    def test_read_all_names(self):
        """read_all_names returns all item names"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"COLLECTS": 100, "TEMP1": 25.5, "CCSDSVER": 0}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        names = packet.read_all_names()
        self.assertIn("COLLECTS", names)
        self.assertIn("TEMP1", names)
        self.assertIn("CCSDSVER", names)

    def test_read_all(self):
        """read_all returns all values"""
        time_nsec = int(time.time() * 1e9)
        json_data = {"COLLECTS": 100, "TEMP1": 25.5}

        packet = JsonPacket("TLM", "INST", "HEALTH_STATUS", time_nsec, False, json_data)

        values = packet.read_all()
        self.assertEqual(values["COLLECTS"], 100)
        self.assertEqual(values["TEMP1"], 25.5)

    def test_time_properties(self):
        """time properties work correctly"""
        time_nsec = int(time.time() * 1e9)
        received_time_nsec = time_nsec + 1000

        packet = JsonPacket(
            "TLM", "INST", "HEALTH_STATUS", time_nsec, False, {}, received_time_nsec_since_epoch=received_time_nsec
        )

        self.assertEqual(packet.time_nsec, time_nsec)
        self.assertEqual(packet.received_time_nsec, received_time_nsec)


if __name__ == "__main__":
    unittest.main()
