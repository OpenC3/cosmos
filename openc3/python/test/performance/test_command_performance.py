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
Performance benchmarks for command building and decom paths.

Run with: poetry run pytest test/performance/test_command_performance.py -v -s
Skip in CI with: CI=true poetry run pytest (tests are skipped when CI env var is set)

For profiling:
    poetry run python -m cProfile -s cumulative test/performance/test_command_performance.py
"""

import os
import sys
import time
import unittest


# Skip all tests in CI environment
if os.environ.get("CI"):
    raise unittest.SkipTest("Skipping performance tests in CI")

from openc3.models.cvt_model import CvtModel
from openc3.system.system import System
from openc3.topics.command_decom_topic import CommandDecomTopic
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from test.test_helper import mock_redis, setup_system


class TestCommandPerformance(unittest.TestCase):
    """Performance benchmarks for command building path"""

    def setUp(self):
        mock_redis(self)
        setup_system()

        # Initialize CVT for all telemetry packets
        for target_name, packets in System.telemetry.all().items():
            for packet_name, packet in packets.items():
                try:
                    json_hash = CvtModel.build_json_from_packet(packet)
                    CvtModel.set(json_hash, target_name, packet_name, scope="DEFAULT")
                except Exception:
                    pass

    def test_build_cmd_performance(self):
        """Benchmark build_cmd with parameters"""
        iterations = int(os.environ.get("PERF_ITERATIONS", 10000))

        print(f"\n{'=' * 70}")
        print("Performance Benchmark: build_cmd")
        print(f"Python Version: {sys.version}")
        print(f"Iterations: {iterations}")
        print(f"{'=' * 70}")

        # Warm up
        for _ in range(10):
            System.commands.build_cmd("INST", "COLLECT", {"TYPE": "NORMAL", "DURATION": 1.0})

        # Benchmark
        start = time.perf_counter()
        for _ in range(iterations):
            System.commands.build_cmd("INST", "COLLECT", {"TYPE": "NORMAL", "DURATION": 1.0})
        elapsed = time.perf_counter() - start

        cmds_per_second = iterations / elapsed
        usec_per_cmd = (elapsed * 1_000_000) / iterations

        print("\nResults:")
        print(f"  Total time:        {elapsed:.4f} seconds")
        print(f"  Commands/second:   {cmds_per_second:.2f}")
        print(f"  Microseconds/cmd:  {usec_per_cmd:.2f}")
        print(f"{'=' * 70}")

    def test_command_decom_topic_write_performance(self):
        """Benchmark CommandDecomTopic.write_packet"""
        iterations = int(os.environ.get("PERF_ITERATIONS", 10000))

        # Build a command packet
        cmd = System.commands.build_cmd("INST", "COLLECT", {"TYPE": "NORMAL", "DURATION": 1.0})

        print(f"\n{'=' * 70}")
        print("Performance Benchmark: CommandDecomTopic.write_packet")
        print(f"Python Version: {sys.version}")
        print(f"Iterations: {iterations}")
        print(f"{'=' * 70}")

        # Warm up
        for _ in range(10):
            CommandDecomTopic.write_packet(cmd, scope="DEFAULT")

        # Benchmark
        start = time.perf_counter()
        for _ in range(iterations):
            CommandDecomTopic.write_packet(cmd, scope="DEFAULT")
        elapsed = time.perf_counter() - start

        writes_per_second = iterations / elapsed
        usec_per_write = (elapsed * 1_000_000) / iterations

        print("\nResults:")
        print(f"  Total time:        {elapsed:.4f} seconds")
        print(f"  Writes/second:     {writes_per_second:.2f}")
        print(f"  Microseconds/write: {usec_per_write:.2f}")
        print(f"{'=' * 70}")


class TestTelemetryDecomPerformance(unittest.TestCase):
    """Performance benchmarks for telemetry decom path"""

    def setUp(self):
        mock_redis(self)
        setup_system()

        # Initialize CVT for all telemetry packets
        for target_name, packets in System.telemetry.all().items():
            for packet_name, packet in packets.items():
                try:
                    json_hash = CvtModel.build_json_from_packet(packet)
                    CvtModel.set(json_hash, target_name, packet_name, scope="DEFAULT")
                except Exception:
                    pass

    def generate_health_status_buffer(self):
        """Generate a realistic HEALTH_STATUS packet buffer"""
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.write("TEMP1", 25.0)
        packet.write("TEMP2", 30.0)
        packet.write("TEMP3", 35.0)
        packet.write("TEMP4", 40.0)
        packet.write("GROUND1STATUS", "CONNECTED")
        packet.write("GROUND2STATUS", "CONNECTED")
        return packet.buffer

    def test_packet_decom_performance(self):
        """Benchmark packet.decom"""
        iterations = int(os.environ.get("PERF_ITERATIONS", 10000))

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.buffer = self.generate_health_status_buffer()

        print(f"\n{'=' * 70}")
        print("Performance Benchmark: packet.decom (HEALTH_STATUS)")
        print(f"Python Version: {sys.version}")
        print(f"Iterations: {iterations}")
        print(f"{'=' * 70}")

        # Warm up
        for _ in range(10):
            packet.decom()

        # Benchmark
        start = time.perf_counter()
        for _ in range(iterations):
            packet.decom()
        elapsed = time.perf_counter() - start

        decoms_per_second = iterations / elapsed
        usec_per_decom = (elapsed * 1_000_000) / iterations

        print("\nResults:")
        print(f"  Total time:        {elapsed:.4f} seconds")
        print(f"  Decoms/second:     {decoms_per_second:.2f}")
        print(f"  Microseconds/decom: {usec_per_decom:.2f}")
        print(f"{'=' * 70}")

    def test_telemetry_decom_topic_write_performance(self):
        """Benchmark TelemetryDecomTopic.write_packet"""
        iterations = int(os.environ.get("PERF_ITERATIONS", 10000))

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.buffer = self.generate_health_status_buffer()

        print(f"\n{'=' * 70}")
        print("Performance Benchmark: TelemetryDecomTopic.write_packet")
        print(f"Python Version: {sys.version}")
        print(f"Iterations: {iterations}")
        print(f"{'=' * 70}")

        # Warm up
        for _ in range(10):
            TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")

        # Benchmark
        start = time.perf_counter()
        for _ in range(iterations):
            TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        elapsed = time.perf_counter() - start

        writes_per_second = iterations / elapsed
        usec_per_write = (elapsed * 1_000_000) / iterations

        print("\nResults:")
        print(f"  Total time:        {elapsed:.4f} seconds")
        print(f"  Writes/second:     {writes_per_second:.2f}")
        print(f"  Microseconds/write: {usec_per_write:.2f}")
        print(f"{'=' * 70}")

    def test_decom_path_breakdown(self):
        """Benchmark breakdown of decom path components"""
        iterations = int(os.environ.get("PERF_ITERATIONS", 10000))

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        buffer = self.generate_health_status_buffer()

        print(f"\n{'=' * 70}")
        print("Performance Benchmark: Decom path breakdown")
        print(f"Python Version: {sys.version}")
        print(f"Iterations: {iterations}")
        print(f"{'=' * 70}")

        # Warm up
        for _ in range(10):
            packet.buffer = buffer
            packet.check_limits(System.limits_set())
            TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")

        # Benchmark buffer assignment
        start = time.perf_counter()
        for _ in range(iterations):
            packet.buffer = buffer
        buffer_time = time.perf_counter() - start

        # Benchmark check_limits
        start = time.perf_counter()
        for _ in range(iterations):
            packet.check_limits(System.limits_set())
        limits_time = time.perf_counter() - start

        # Benchmark TelemetryDecomTopic.write_packet
        start = time.perf_counter()
        for _ in range(iterations):
            TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        write_time = time.perf_counter() - start

        total_time = buffer_time + limits_time + write_time

        print("\nBreakdown:")
        print(
            f"  packet.buffer=:           {(buffer_time * 1_000_000 / iterations):.2f} μs ({buffer_time / total_time * 100:.1f}%)"
        )
        print(
            f"  packet.check_limits:      {(limits_time * 1_000_000 / iterations):.2f} μs ({limits_time / total_time * 100:.1f}%)"
        )
        print(
            f"  TelemetryDecomTopic.write: {(write_time * 1_000_000 / iterations):.2f} μs ({write_time / total_time * 100:.1f}%)"
        )
        print("  ----------------------------------------")
        print(f"  Total:                    {(total_time * 1_000_000 / iterations):.2f} μs")
        print(f"{'=' * 70}")


if __name__ == "__main__":
    unittest.main()
