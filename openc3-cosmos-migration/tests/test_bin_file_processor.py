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
Tests for BinFileProcessor and related utilities.
"""

import gzip
import os
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone

# Add parent directory to path so we can import openc3
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "openc3", "python"))

from openc3.logs.packet_log_writer import PacketLogWriter
from openc3.packets.json_packet import JsonPacket

from bin_file_processor import (
    BinFileProcessor,
    extract_timestamp_from_filename,
    parse_target_packet_from_filename,
)


class TestBinFileProcessor(unittest.TestCase):
    """Tests for BinFileProcessor class."""

    def setUp(self):
        self.processor = BinFileProcessor()
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        # Clean up temp files
        for f in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, f))
        os.rmdir(self.temp_dir)

    def _create_json_log_file(self):
        """Create a test log file with JSON packets."""
        plw = PacketLogWriter(self.temp_dir, "test")
        time_nsec = int(time.time() * 1e9)

        # Write 3 JSON packets
        for i in range(3):
            pkt_data = {"COLLECTS": 100 + i, "TEMP1": 25.5 + i}
            plw.write("JSON_PACKET", "TLM", "INST", "HEALTH_STATUS", time_nsec + i * 1000, True, pkt_data, None, "0-0")

        filename = plw.filename
        plw.shutdown()
        return filename

    def _create_raw_log_file(self):
        """Create a test log file with raw packets only."""
        plw = PacketLogWriter(self.temp_dir, "test")
        time_nsec = int(time.time() * 1e9)

        # Write 3 raw packets
        for i in range(3):
            pkt_data = bytes([0x00, 0x01, 0x02, 0x03 + i])
            plw.write("RAW_PACKET", "TLM", "INST", "HEALTH_STATUS", time_nsec + i * 1000, True, pkt_data, None, "0-0")

        filename = plw.filename
        plw.shutdown()
        return filename

    def _create_mixed_log_file(self):
        """Create a test log file with both raw and JSON packets."""
        plw = PacketLogWriter(self.temp_dir, "test")
        time_nsec = int(time.time() * 1e9)

        # Write alternating raw and JSON packets
        for i in range(3):
            # Raw packet
            raw_data = bytes([0x00, 0x01, 0x02, 0x03 + i])
            plw.write("RAW_PACKET", "TLM", "INST", "RAW_PKT", time_nsec + i * 2000, True, raw_data, None, "0-0")
            # JSON packet
            json_data = {"VALUE": 100 + i}
            plw.write(
                "JSON_PACKET", "TLM", "INST", "JSON_PKT", time_nsec + i * 2000 + 1000, True, json_data, None, "0-0"
            )

        filename = plw.filename
        plw.shutdown()
        return filename

    def test_process_file_with_json_packets(self):
        """process_file yields JsonPacket objects from log file"""
        log_file = self._create_json_log_file()

        packets = list(self.processor.process_file(log_file))

        self.assertEqual(len(packets), 3)
        for i, packet in enumerate(packets):
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.target_name, "INST")
            self.assertEqual(packet.packet_name, "HEALTH_STATUS")
            self.assertEqual(packet.read("COLLECTS"), 100 + i)

    def test_process_file_skips_raw_packets(self):
        """process_file only yields JSON packets, not raw packets"""
        log_file = self._create_raw_log_file()

        packets = list(self.processor.process_file(log_file))

        # Should return no packets since all are raw
        self.assertEqual(len(packets), 0)

    def test_process_file_filters_to_json_only(self):
        """process_file filters mixed log to only JSON packets"""
        log_file = self._create_mixed_log_file()

        packets = list(self.processor.process_file(log_file))

        # Should only return JSON packets (3 of them)
        self.assertEqual(len(packets), 3)
        for packet in packets:
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.packet_name, "JSON_PKT")

    def test_process_file_with_gzip(self):
        """process_file handles gzipped log files"""
        # Create a regular log file
        log_file = self._create_json_log_file()

        # Compress it
        gz_file = log_file + ".gz"
        with open(log_file, "rb") as f_in:
            with gzip.open(gz_file, "wb") as f_out:
                f_out.write(f_in.read())

        # Process the gzipped file
        packets = list(self.processor.process_file(gz_file))

        self.assertEqual(len(packets), 3)
        for i, packet in enumerate(packets):
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.read("COLLECTS"), 100 + i)

        # Clean up
        os.remove(gz_file)

    def test_process_bytes(self):
        """process_bytes processes raw bytes of log file"""
        log_file = self._create_json_log_file()

        # Read file as bytes
        with open(log_file, "rb") as f:
            data = f.read()

        packets = list(self.processor.process_bytes(data))

        self.assertEqual(len(packets), 3)
        for i, packet in enumerate(packets):
            self.assertIsInstance(packet, JsonPacket)
            self.assertEqual(packet.read("COLLECTS"), 100 + i)

    def test_process_bytes_cleans_up_temp_file(self):
        """process_bytes removes temp file after processing"""
        log_file = self._create_json_log_file()

        with open(log_file, "rb") as f:
            data = f.read()

        # Count temp files before
        temp_dir = tempfile.gettempdir()
        before_count = len([f for f in os.listdir(temp_dir) if f.endswith(".bin")])

        # Process bytes (consume the generator)
        list(self.processor.process_bytes(data))

        # Count temp files after - should be same or fewer
        after_count = len([f for f in os.listdir(temp_dir) if f.endswith(".bin")])
        self.assertLessEqual(after_count, before_count)

    def test_processor_with_logger(self):
        """BinFileProcessor accepts a logger"""
        # Just verify it doesn't crash with a mock logger
        class MockLogger:
            def info(self, msg):
                pass

            def warn(self, msg):
                pass

            def error(self, msg):
                pass

        processor = BinFileProcessor(logger=MockLogger())
        log_file = self._create_json_log_file()
        packets = list(processor.process_file(log_file))
        self.assertEqual(len(packets), 3)


class TestExtractTimestampFromFilename(unittest.TestCase):
    """Tests for extract_timestamp_from_filename function."""

    def test_valid_filename(self):
        """extracts timestamp from valid decom log filename"""
        # Filename format: yyyymmddhhmmssmmmuuunnn__TARGET__PACKET__rt__decom.bin.gz
        filename = "20240115123045123456789__INST__HEALTH_STATUS__rt__decom.bin.gz"

        result = extract_timestamp_from_filename(filename)

        # Should parse: 2024-01-15 12:30:45.123
        expected_dt = datetime(2024, 1, 15, 12, 30, 45, 123000)
        expected_nsec = int(expected_dt.timestamp() * 1_000_000_000)
        self.assertEqual(result, expected_nsec)

    def test_valid_filename_with_path(self):
        """extracts timestamp from filename with directory path"""
        filename = "/path/to/logs/20240115123045123456789__INST__HEALTH_STATUS__rt__decom.bin.gz"

        result = extract_timestamp_from_filename(filename)

        expected_dt = datetime(2024, 1, 15, 12, 30, 45, 123000)
        expected_nsec = int(expected_dt.timestamp() * 1_000_000_000)
        self.assertEqual(result, expected_nsec)

    def test_short_timestamp(self):
        """returns 0 for filename with short timestamp"""
        filename = "2024011512__INST__HEALTH_STATUS__rt__decom.bin.gz"

        result = extract_timestamp_from_filename(filename)

        self.assertEqual(result, 0)

    def test_invalid_timestamp(self):
        """returns 0 for filename with invalid timestamp"""
        filename = "NOTAVALIDTIMESTAMP__INST__HEALTH_STATUS__rt__decom.bin.gz"

        result = extract_timestamp_from_filename(filename)

        self.assertEqual(result, 0)

    def test_empty_filename(self):
        """returns 0 for empty filename"""
        result = extract_timestamp_from_filename("")

        self.assertEqual(result, 0)

    def test_no_underscores(self):
        """returns 0 for filename without double underscores"""
        filename = "somefile.bin"

        result = extract_timestamp_from_filename(filename)

        self.assertEqual(result, 0)

    def test_just_timestamp(self):
        """extracts timestamp from filename with only timestamp"""
        filename = "20240115123045123456789.bin"

        result = extract_timestamp_from_filename(filename)

        expected_dt = datetime(2024, 1, 15, 12, 30, 45, 123000)
        expected_nsec = int(expected_dt.timestamp() * 1_000_000_000)
        self.assertEqual(result, expected_nsec)


class TestParseTargetPacketFromFilename(unittest.TestCase):
    """Tests for parse_target_packet_from_filename function."""

    def test_valid_filename(self):
        """extracts target and packet from valid filename"""
        filename = "20240115123045123456789__INST__HEALTH_STATUS__rt__decom.bin.gz"

        target, packet = parse_target_packet_from_filename(filename)

        self.assertEqual(target, "INST")
        self.assertEqual(packet, "HEALTH_STATUS")

    def test_valid_filename_with_path(self):
        """extracts target and packet from filename with path"""
        filename = "/path/to/logs/20240115123045123456789__INST__HEALTH_STATUS__rt__decom.bin.gz"

        target, packet = parse_target_packet_from_filename(filename)

        self.assertEqual(target, "INST")
        self.assertEqual(packet, "HEALTH_STATUS")

    def test_command_filename(self):
        """extracts target and packet from command log filename"""
        filename = "20240115123045123456789__INST__COLLECT__rt__cmd.bin.gz"

        target, packet = parse_target_packet_from_filename(filename)

        self.assertEqual(target, "INST")
        self.assertEqual(packet, "COLLECT")

    def test_insufficient_parts(self):
        """returns None for filename with insufficient parts"""
        filename = "20240115123045123456789__INST.bin"

        target, packet = parse_target_packet_from_filename(filename)

        self.assertIsNone(target)
        self.assertIsNone(packet)

    def test_no_underscores(self):
        """returns None for filename without double underscores"""
        filename = "somefile.bin"

        target, packet = parse_target_packet_from_filename(filename)

        self.assertIsNone(target)
        self.assertIsNone(packet)

    def test_empty_filename(self):
        """returns None for empty filename"""
        target, packet = parse_target_packet_from_filename("")

        self.assertIsNone(target)
        self.assertIsNone(packet)

    def test_target_with_underscores(self):
        """handles target/packet names that don't contain double underscores"""
        filename = "20240115123045123456789__MY_TARGET__MY_PACKET__rt__decom.bin.gz"

        target, packet = parse_target_packet_from_filename(filename)

        # Note: Single underscores within names are preserved
        self.assertEqual(target, "MY_TARGET")
        self.assertEqual(packet, "MY_PACKET")


if __name__ == "__main__":
    unittest.main()
