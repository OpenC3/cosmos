# Copyright 2026 OpenC3, Inc.
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
Tests for PacketLogWriter class.
Based on Ruby spec/logs/packet_log_writer_spec.rb
"""

import os
import sys
import tempfile
import time
import unittest


# Add parent directories to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from openc3.logs.packet_log_constants import (
    OPENC3_FILE_HEADER,
    OPENC3_MAX_PACKET_INDEX,
    OPENC3_MAX_TARGET_INDEX,
)
from openc3.logs.packet_log_reader import PacketLogReader
from openc3.logs.packet_log_writer import PacketLogWriter


class TestPacketLogWriter(unittest.TestCase):
    """Tests for PacketLogWriter class."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.files_created = []

    def tearDown(self):
        # Clean up temp files
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def test_write_binary_data_to_file(self):
        """writes binary data to a binary file"""
        first_time = int(time.time() * 1e9)
        last_time = first_time + 1_000_000_000

        plw = PacketLogWriter(self.temp_dir, "test")
        self.assertEqual(plw.file_size, 0)

        # Mark the first packet as "stored" (True)
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", first_time, True, b"\x01\x02", None, "0-0")
        self.assertNotEqual(plw.file_size, 0)

        plw.write("RAW_PACKET", "TLM", "TGT2", "PKT2", last_time, False, b"\x03\x04", None, "0-0")
        filename = plw.filename
        plw.shutdown()

        # Verify the file exists and has the OPENC3 header
        self.assertTrue(os.path.exists(filename))
        with open(filename, "rb") as f:
            header = f.read(8)
            self.assertEqual(header, OPENC3_FILE_HEADER)

        # Verify the packets by using PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)

        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        self.assertTrue(pkt.stored)
        self.assertEqual(pkt.buffer, b"\x01\x02")

        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT2")
        self.assertEqual(pkt.packet_name, "PKT2")
        self.assertFalse(pkt.stored)
        self.assertEqual(pkt.buffer, b"\x03\x04")

        pkt = reader.read()
        self.assertIsNone(pkt)
        reader.close()

    def test_write_json_packets(self):
        """writes JSON packets to a file"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test")

        # Write JSON packet
        json_data = {"ITEM1": 100, "ITEM2": 200.5, "ITEM3": "text"}
        plw.write("JSON_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, json_data, None, "0-0")

        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)

        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        # JsonPacket stores data in json_hash
        self.assertEqual(pkt.json_hash.get("ITEM1"), 100)
        self.assertEqual(pkt.json_hash.get("ITEM2"), 200.5)
        self.assertEqual(pkt.json_hash.get("ITEM3"), "text")

        reader.close()

    def test_write_cmd_packets(self):
        """writes command packets with CMD flag"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test")
        plw.write("RAW_PACKET", "CMD", "TGT1", "CMD1", time_nsec, False, b"\x01\x02", None, "0-0")
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)

        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "CMD1")
        self.assertEqual(pkt.cmd_or_tlm, "CMD")

        reader.close()

    def test_correctly_writes_multiple_files(self):
        """correctly writes multiple files in a row"""
        first_time = int(time.time() * 1e9)
        last_time = first_time + 1_000_000_000
        first_time2 = first_time + 1
        last_time2 = last_time + 1

        plw = PacketLogWriter(self.temp_dir, "test")
        self.assertEqual(plw.file_size, 0)

        # Write first file
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", first_time, True, b"\x01\x02", None, "0-0")
        self.assertNotEqual(plw.file_size, 0)
        plw.write("RAW_PACKET", "TLM", "TGT2", "PKT2", last_time, False, b"\x03\x04", None, "0-0")
        filename1 = plw.filename

        # Start new file
        plw.start_new_file()
        self.assertEqual(plw.file_size, len(OPENC3_FILE_HEADER))

        plw.write("RAW_PACKET", "TLM", "TGT2", "PKT2", first_time2, False, b"\x03\x04", None, "0-0")
        self.assertNotEqual(plw.file_size, len(OPENC3_FILE_HEADER))
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", last_time2, True, b"\x01\x02", None, "0-0")
        filename2 = plw.filename
        plw.shutdown()

        # Both files should exist
        self.assertTrue(os.path.exists(filename1))
        self.assertTrue(os.path.exists(filename2))
        self.assertNotEqual(filename1, filename2)

        # Verify first file
        reader = PacketLogReader()
        reader.open(filename1)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        self.assertTrue(pkt.stored)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT2")
        self.assertEqual(pkt.packet_name, "PKT2")
        self.assertFalse(pkt.stored)
        pkt = reader.read()
        self.assertIsNone(pkt)
        reader.close()

        # Verify second file
        reader.open(filename2)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT2")
        self.assertEqual(pkt.packet_name, "PKT2")
        self.assertFalse(pkt.stored)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        self.assertTrue(pkt.stored)
        pkt = reader.read()
        self.assertIsNone(pkt)
        reader.close()

    def test_shutdown_closes_file(self):
        """shutdown closes the file"""
        plw = PacketLogWriter(self.temp_dir, "test")
        plw.write("RAW_PACKET", "CMD", "TGT", "CMD", int(time.time() * 1e9), True, b"\x01\x02", None, "0-0")
        self.assertNotEqual(plw.file_size, 0)
        filename = plw.filename

        plw.shutdown()
        # File should be closed (written and flushed)
        self.assertTrue(os.path.exists(filename))

    def test_write_with_id(self):
        """writes packets with 64-character hex ID"""
        time_nsec = int(time.time() * 1e9)
        packet_id = "a" * 64  # 64 hex characters

        plw = PacketLogWriter(self.temp_dir, "test")
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, b"\x01\x02", packet_id, "0-0")
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        # Note: ID is stored in packet but not exposed in current implementation
        reader.close()

    def test_write_with_invalid_id_raises(self):
        """raises error when id is not 64 characters"""
        plw = PacketLogWriter(self.temp_dir, "test")

        with self.assertRaises(ValueError) as context:
            plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", int(time.time() * 1e9), False, b"\x01\x02", "short_id", "0-0")

        self.assertIn("64", str(context.exception))
        plw.shutdown()

    def test_write_with_received_time(self):
        """writes packets with separate received time"""
        time_nsec = int(time.time() * 1e9)
        received_time_nsec = time_nsec + 100_000_000  # 100ms later

        plw = PacketLogWriter(self.temp_dir, "test")
        plw.write(
            "RAW_PACKET",
            "TLM",
            "TGT1",
            "PKT1",
            time_nsec,
            False,
            b"\x01\x02",
            None,
            "0-0",
            received_time_nsec_since_epoch=received_time_nsec,
        )
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        # Raw packets have _time_nsec and _received_time_nsec set by reader
        self.assertEqual(pkt._time_nsec, time_nsec)
        self.assertEqual(pkt._received_time_nsec, received_time_nsec)
        reader.close()

    def test_write_with_extra_metadata(self):
        """writes packets with extra metadata"""
        time_nsec = int(time.time() * 1e9)
        extra = {"custom_field": "value", "count": 42}

        plw = PacketLogWriter(self.temp_dir, "test")
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, b"\x01\x02", None, "0-0", extra=extra)
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)
        pkt = reader.read()
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.extra.get("custom_field"), "value")
        self.assertEqual(pkt.extra.get("count"), 42)
        reader.close()

    def test_target_index_overflow(self):
        """raises error after max target index exceeded"""
        plw = PacketLogWriter(self.temp_dir, "test")

        # Write max + 2 targets (0 to max are valid, so +1 is ok, +2 errors)
        with self.assertRaises(ValueError) as context:
            for i in range(OPENC3_MAX_TARGET_INDEX + 2):
                plw.write("RAW_PACKET", "TLM", f"TGT{i}", "PKT", int(time.time() * 1e9), True, b"\x01\x02", None, "0-0")

        self.assertIn("Target Index Overflow", str(context.exception))
        plw.shutdown()

    def test_packet_index_overflow(self):
        """raises error after max packet index exceeded"""
        plw = PacketLogWriter(self.temp_dir, "test")

        # Write max + 2 packets (0 to max are valid, so +1 is ok, +2 errors)
        with self.assertRaises(ValueError) as context:
            for i in range(OPENC3_MAX_PACKET_INDEX + 2):
                plw.write("RAW_PACKET", "TLM", "TGT", f"PKT{i}", int(time.time() * 1e9), True, b"\x01\x02", None, "0-0")

        self.assertIn("Packet Index Overflow", str(context.exception))
        plw.shutdown()

    def test_write_cbor_format(self):
        """writes JSON packets in CBOR format"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test", data_format="CBOR")
        json_data = {"ITEM1": 100, "ITEM2": 200.5}
        plw.write("JSON_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, json_data, None, "0-0")
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)
        pkt = reader.read()
        self.assertEqual(pkt.json_hash.get("ITEM1"), 100)
        self.assertEqual(pkt.json_hash.get("ITEM2"), 200.5)
        reader.close()

    def test_write_json_format(self):
        """writes JSON packets in JSON format"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test", data_format="JSON")
        json_data = {"ITEM1": 100, "ITEM2": 200.5}
        plw.write("JSON_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, json_data, None, "0-0")
        filename = plw.filename
        plw.shutdown()

        # Verify with PacketLogReader
        reader = PacketLogReader()
        reader.open(filename)
        pkt = reader.read()
        self.assertEqual(pkt.json_hash.get("ITEM1"), 100)
        self.assertEqual(pkt.json_hash.get("ITEM2"), 200.5)
        reader.close()

    def test_filename_property(self):
        """filename property returns current log filename"""
        plw = PacketLogWriter(self.temp_dir, "test")
        self.assertIsNone(plw.filename)  # No file yet

        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", int(time.time() * 1e9), False, b"\x01\x02", None, "0-0")
        self.assertIsNotNone(plw.filename)
        self.assertTrue(plw.filename.endswith(".bin"))
        self.assertIn("test", plw.filename)

        plw.shutdown()

    def test_file_size_property(self):
        """file_size property tracks current file size"""
        plw = PacketLogWriter(self.temp_dir, "test")
        self.assertEqual(plw.file_size, 0)

        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", int(time.time() * 1e9), False, b"\x01\x02", None, "0-0")
        size_after_one = plw.file_size
        self.assertGreater(size_after_one, len(OPENC3_FILE_HEADER))

        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", int(time.time() * 1e9), False, b"\x03\x04", None, "0-0")
        size_after_two = plw.file_size
        self.assertGreater(size_after_two, size_after_one)

        plw.shutdown()

    def test_reuses_target_packet_declarations(self):
        """reuses target and packet declarations for same target/packet"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test")

        # Write same target/packet multiple times
        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", time_nsec, False, b"\x01", None, "0-0")
        size_after_first = plw.file_size

        plw.write("RAW_PACKET", "TLM", "TGT1", "PKT1", time_nsec + 1000, False, b"\x02", None, "0-0")
        size_increase = plw.file_size - size_after_first

        # Second write should be smaller than first (no declarations)
        # First write includes: header + target decl + packet decl + packet
        # Second write includes: only packet (target/packet already declared)
        self.assertLess(size_increase, size_after_first - len(OPENC3_FILE_HEADER))

        plw.shutdown()

    def test_unknown_entry_type_raises(self):
        """raises error with unknown entry type"""
        plw = PacketLogWriter(self.temp_dir, "test")

        with self.assertRaises(ValueError) as context:
            plw.write("UNKNOWN_TYPE", "TLM", "TGT1", "PKT1", int(time.time() * 1e9), False, b"\x01\x02", None, "0-0")

        self.assertIn("Unknown entry_type", str(context.exception))
        plw.shutdown()


class TestPacketLogWriterRoundTrip(unittest.TestCase):
    """Round-trip tests using PacketLogWriter and PacketLogReader together."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def test_roundtrip_multiple_targets_packets(self):
        """round trips multiple targets and packets"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test")

        # Use unique target/packet names to avoid conflicts with System definitions
        # that may be set up by other tests (which would cause buffer size mismatches)
        plw.write("RAW_PACKET", "TLM", "TEST_TGT1", "TEST_PKT1", time_nsec, False, b"\x01\x02\x03\x04", None, "0-0")
        plw.write("RAW_PACKET", "TLM", "TEST_TGT1", "TEST_PKT2", time_nsec + 1000, True, b"\x05\x06", None, "0-0")
        plw.write("RAW_PACKET", "TLM", "TEST_TGT2", "TEST_PKT1", time_nsec + 2000, False, b"\x07\x08", None, "0-0")
        plw.write("RAW_PACKET", "CMD", "TEST_TGT1", "TEST_CMD1", time_nsec + 3000, False, b"\x09", None, "0-0")

        filename = plw.filename
        plw.shutdown()

        # Read back and verify
        reader = PacketLogReader()
        packets = list(reader.each(filename))

        self.assertEqual(len(packets), 4)

        self.assertEqual(packets[0].target_name, "TEST_TGT1")
        self.assertEqual(packets[0].packet_name, "TEST_PKT1")
        self.assertEqual(packets[0].buffer, b"\x01\x02\x03\x04")
        self.assertEqual(packets[0].cmd_or_tlm, "TLM")
        self.assertFalse(packets[0].stored)

        self.assertEqual(packets[1].target_name, "TEST_TGT1")
        self.assertEqual(packets[1].packet_name, "TEST_PKT2")
        self.assertTrue(packets[1].stored)

        self.assertEqual(packets[2].target_name, "TEST_TGT2")
        self.assertEqual(packets[2].packet_name, "TEST_PKT1")

        self.assertEqual(packets[3].target_name, "TEST_TGT1")
        self.assertEqual(packets[3].packet_name, "TEST_CMD1")
        self.assertEqual(packets[3].cmd_or_tlm, "CMD")

    def test_roundtrip_json_with_key_compression(self):
        """round trips JSON packets with key map compression"""
        time_nsec = int(time.time() * 1e9)

        plw = PacketLogWriter(self.temp_dir, "test", data_format="CBOR")

        # Write multiple JSON packets - should use key map compression
        for i in range(3):
            json_data = {"COLLECTS": 100 + i, "TEMP1": 25.5 + i, "STATUS": "NOMINAL"}
            plw.write("JSON_PACKET", "TLM", "INST", "HEALTH_STATUS", time_nsec + i * 1000, False, json_data, None, "0-0")

        filename = plw.filename
        plw.shutdown()

        # Read back and verify
        reader = PacketLogReader()
        packets = list(reader.each(filename))

        self.assertEqual(len(packets), 3)
        for i, pkt in enumerate(packets):
            self.assertEqual(pkt.json_hash.get("COLLECTS"), 100 + i)
            self.assertEqual(pkt.json_hash.get("TEMP1"), 25.5 + i)
            self.assertEqual(pkt.json_hash.get("STATUS"), "NOMINAL")


if __name__ == "__main__":
    unittest.main()
