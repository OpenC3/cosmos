# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""Compare equivalent OpenC3 pure Ruby and Python methods.

Ruby runs with YJIT and OPENC3_NO_EXT=1. Python runs the same workloads in this
process. The Ruby worker is shared with c_extensions_benchmark.rb so workload
inputs and units stay aligned.
"""

import gc
import io
import json
import math
import os
import statistics
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))
os.environ["OPENC3_NO_STORE"] = "1"

from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.config.config_parser import ConfigParser
from openc3.conversions.polynomial_conversion import PolynomialConversion
from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.packets.packet import Packet
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry
from openc3.utilities.crc import Crc32
from openc3.utilities.extract import remove_quotes


@dataclass
class BenchmarkCase:
    extension: str
    name: str
    units: int
    run: Callable[[], None]
    signature: Callable[[], object]


def build_cases() -> list[BenchmarkCase]:
    cases = []

    def add_case(extension, name, units, run, signature):
        cases.append(BenchmarkCase(extension, name, units, run, signature))

    quoted = '"telemetry value with spaces"'

    def remove_quotes_run():
        for _ in range(10_000):
            remove_quotes(quoted)

    add_case(
        "string",
        "remove_quotes",
        10_000,
        remove_quotes_run,
        lambda: remove_quotes(quoted),
    )

    polynomial = PolynomialConversion(1.25, -0.5, 0.125, 0.01, -0.001)

    def polynomial_run():
        for _ in range(10_000):
            polynomial.call(12.5, None, None)

    add_case(
        "polynomial_conversion",
        "call (5 coefficients)",
        10_000,
        polynomial_run,
        lambda: polynomial.call(12.5, None, None),
    )

    crc32 = Crc32()
    crc_small = bytes(range(32))
    crc_large = crc_small * 128

    def crc_small_run():
        for _ in range(500):
            crc32.calc(crc_small)

    def crc_large_run():
        for _ in range(10):
            crc32.calc(crc_large)

    add_case(
        "crc",
        "CRC32 (32 bytes)",
        500,
        crc_small_run,
        lambda: crc32.calc(crc_small),
    )
    add_case(
        "crc",
        "CRC32 (4KB)",
        10,
        crc_large_run,
        lambda: crc32.calc(crc_large),
    )

    binary_data = bytes(range(64))

    def read_binary():
        for _ in range(10_000):
            BinaryAccessor.read(13, 32, "UINT", binary_data, "BIG_ENDIAN")

    add_case(
        "packet/structure",
        "BinaryAccessor.read UINT32",
        10_000,
        read_binary,
        lambda: BinaryAccessor.read(13, 32, "UINT", binary_data, "BIG_ENDIAN"),
    )

    def write_binary():
        for _ in range(10_000):
            BinaryAccessor.write(
                0x12345678,
                13,
                32,
                "UINT",
                bytearray(binary_data),
                "BIG_ENDIAN",
                "ERROR",
            )

    def write_binary_signature():
        data = bytearray(binary_data)
        BinaryAccessor.write(0x12345678, 13, 32, "UINT", data, "BIG_ENDIAN", "ERROR")
        return data.hex()

    add_case(
        "packet/structure",
        "BinaryAccessor.write UINT32",
        10_000,
        write_binary,
        write_binary_signature,
    )

    packet = Packet("target", "packet", "BIG_ENDIAN")
    packet.define_item("VALUE", 0, 16, "UINT")
    packet.write("VALUE", 42)
    item = packet.get_item("VALUE")

    def read_item():
        for _ in range(10_000):
            packet.read_item(item)

    def new_packet():
        for _ in range(1_000):
            Packet("target", "packet", "BIG_ENDIAN")

    add_case(
        "packet/structure",
        "Structure#read_item",
        10_000,
        read_item,
        lambda: packet.read_item(item),
    )
    add_case(
        "packet/structure",
        "Packet.new",
        1_000,
        new_packet,
        lambda: packet_signature(Packet("target", "packet", "BIG_ENDIAN")),
    )

    telemetry_config = PacketConfig()
    telemetry_config.telemetry = {"TARGET": {"PACKET": packet}}
    telemetry = Telemetry(telemetry_config, object())

    def packet_lookup():
        for _ in range(10_000):
            telemetry.packet("target", "packet")

    def value_lookup():
        for _ in range(5_000):
            telemetry.value("target", "packet", "value", "RAW")

    add_case(
        "telemetry",
        "packet lookup",
        10_000,
        packet_lookup,
        lambda: telemetry.packet("target", "packet").packet_name,
    )
    add_case(
        "telemetry",
        "value lookup and read",
        5_000,
        value_lookup,
        lambda: telemetry.value("target", "packet", "value", "RAW"),
    )

    config_text = "".join(
        f'KEYWORD{index % 10} PARAM{index} "description {index}" # comment\n'
        for index in range(500)
    )
    config_io = io.StringIO(config_text)
    parser = ConfigParser()

    def parse_config():
        config_io.seek(0)
        return sum(
            1
            for _keyword, _params in parser.parse_loop(
                config_io,
                False,
                True,
                len(config_text),
                ConfigParser.PARSING_REGEX,
            )
        )

    add_case(
        "config_parser", "parse_loop (config lines)", 500, parse_config, parse_config
    )

    burst = BurstProtocol(4, "1ACFFC1D", False, None)
    burst_data = b"\x1a\xcf\xfc\x1d" + (b"x" * 252)

    def burst_run():
        for _ in range(1_000):
            burst.read_data(burst_data)

    add_case(
        "burst_protocol",
        "read_data (256-byte synced burst)",
        1_000,
        burst_run,
        lambda: len(burst.read_data(burst_data)[0]),
    )

    return cases


def packet_signature(packet):
    return [packet.target_name, packet.packet_name, packet.received_count]


def run_python(cases, warmup_seconds, sample_seconds, sample_count):
    results = []
    for benchmark in cases:
        warmup_started = time.perf_counter()
        warmup_runs = 0
        while True:
            benchmark.run()
            warmup_runs += 1
            warmup_elapsed = time.perf_counter() - warmup_started
            if warmup_elapsed >= warmup_seconds:
                break
        runs_per_sample = max(
            math.ceil(warmup_runs * sample_seconds / warmup_elapsed), 1
        )

        samples = []
        for _ in range(sample_count):
            gc.collect()
            started = time.perf_counter()
            for _ in range(runs_per_sample):
                benchmark.run()
            elapsed = time.perf_counter() - started
            samples.append(runs_per_sample * benchmark.units / elapsed)

        mean = statistics.fmean(samples)
        results.append(
            {
                "extension": benchmark.extension,
                "name": benchmark.name,
                "ips": statistics.median(samples),
                "cv_percent": 0.0
                if mean == 0.0
                else statistics.pstdev(samples, mu=mean) / mean * 100.0,
                "signature": benchmark.signature(),
            }
        )
    return results


def run_ruby(warmup_seconds, sample_seconds, sample_count, benchmark_filter, *, yjit):
    environment = os.environ.copy()
    environment.update(
        {
            "OPENC3_NO_STORE": "1",
            "OPENC3_BENCHMARK_WARMUP": str(warmup_seconds),
            "OPENC3_BENCHMARK_TIME": str(sample_seconds),
            "OPENC3_BENCHMARK_SAMPLES": str(sample_count),
        }
    )
    environment["OPENC3_NO_EXT"] = "1"
    if benchmark_filter:
        environment["OPENC3_BENCHMARK_FILTER"] = benchmark_filter
    command = [
        "bundle",
        "exec",
        os.environ.get("RUBY", "ruby"),
        "--yjit" if yjit else "--disable-yjit",
        "-I",
        str(ROOT / "lib"),
        str(ROOT / "test/benchmarks/c_extensions_benchmark.rb"),
        "--worker",
    ]
    completed = subprocess.run(
        command, cwd=ROOT, env=environment, text=True, capture_output=True, check=False
    )
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"Ruby benchmark failed ({completed.returncode})")
    return json.loads(completed.stdout)


def format_rate(rate):
    if rate >= 1_000_000:
        return f"{rate / 1_000_000.0:.2f}M"
    if rate >= 1_000:
        return f"{rate / 1_000.0:.1f}k"
    return f"{rate:.1f}"


def main():
    warmup_seconds = float(os.environ.get("OPENC3_BENCHMARK_WARMUP", "0.25"))
    sample_seconds = float(os.environ.get("OPENC3_BENCHMARK_TIME", "0.5"))
    sample_count = int(os.environ.get("OPENC3_BENCHMARK_SAMPLES", "5"))
    benchmark_filter = os.environ.get("OPENC3_BENCHMARK_FILTER")

    cases = build_cases()
    if benchmark_filter:
        cases = [
            benchmark
            for benchmark in cases
            if benchmark_filter in benchmark.extension
            or benchmark_filter in benchmark.name
        ]
    if not cases:
        raise RuntimeError(
            f"No shared benchmarks matched OPENC3_BENCHMARK_FILTER={benchmark_filter!r}"
        )

    print("Running pure Ruby benchmarks with YJIT...")
    ruby_yjit = run_ruby(
        warmup_seconds, sample_seconds, sample_count, benchmark_filter, yjit=True
    )
    print("Running pure Ruby benchmarks without YJIT...")
    ruby_no_yjit = run_ruby(
        warmup_seconds, sample_seconds, sample_count, benchmark_filter, yjit=False
    )
    print("Running Python benchmarks...")
    python_results = run_python(cases, warmup_seconds, sample_seconds, sample_count)

    ruby_yjit_by_name = {
        (result["extension"], result["name"]): result for result in ruby_yjit["results"]
    }
    ruby_no_yjit_by_name = {
        (result["extension"], result["name"]): result
        for result in ruby_no_yjit["results"]
    }
    rows = []
    mismatches = []
    for python_result in python_results:
        key = (python_result["extension"], python_result["name"])
        ruby_yjit_result = ruby_yjit_by_name[key]
        ruby_no_yjit_result = ruby_no_yjit_by_name[key]
        if not (
            ruby_yjit_result["signature"]
            == ruby_no_yjit_result["signature"]
            == python_result["signature"]
        ):
            mismatches.append(
                (
                    key,
                    ruby_yjit_result["signature"],
                    ruby_no_yjit_result["signature"],
                    python_result["signature"],
                )
            )
        rows.append(
            (
                *key,
                ruby_yjit_result["ips"],
                ruby_no_yjit_result["ips"],
                python_result["ips"],
                ruby_yjit_result["ips"] / ruby_no_yjit_result["ips"],
                ruby_yjit_result["ips"] / python_result["ips"],
                ruby_no_yjit_result["ips"] / python_result["ips"],
                ruby_yjit_result["cv_percent"],
                ruby_no_yjit_result["cv_percent"],
                python_result["cv_percent"],
            )
        )

    if mismatches:
        for (
            extension,
            name,
        ), yjit_signature, no_yjit_signature, python_signature in mismatches:
            print(
                f"Correctness mismatch for {extension}: {name}: Ruby YJIT={yjit_signature!r}, "
                f"Ruby no YJIT={no_yjit_signature!r}, Python={python_signature!r}",
                file=sys.stderr,
            )
        raise RuntimeError("Refusing to compare implementations with different results")

    print()
    print(f"Ruby with YJIT: {ruby_yjit['ruby']}")
    print(f"Ruby without YJIT: {ruby_no_yjit['ruby']}")
    print(f"Python: {sys.version.splitlines()[0]}")
    print(
        f"Median of {sample_count} samples; {sample_seconds}s/sample after {warmup_seconds}s warmup"
    )
    print("Rates are equivalent method calls or parsed lines per second as named.")
    print()
    header = (
        f"{'Component':<23} {'Workload':<43} {'Ruby YJIT':>11} {'No YJIT':>11} {'Python':>11} "
        f"{'YJIT gain':>10} {'YJIT/Py':>9} {'NoJIT/Py':>9} {'sample CV':>14}"
    )
    print(header)
    print("-" * len(header))
    for (
        extension,
        name,
        yjit_ips,
        no_yjit_ips,
        python_ips,
        yjit_gain,
        yjit_python,
        no_yjit_python,
        yjit_cv,
        no_yjit_cv,
        python_cv,
    ) in rows:
        print(
            f"{extension:<23} {name:<43} {format_rate(yjit_ips):>11} {format_rate(no_yjit_ips):>11} "
            f"{format_rate(python_ips):>11} {yjit_gain:>9.2f}x {yjit_python:>8.2f}x "
            f"{no_yjit_python:>8.2f}x {yjit_cv:>4.1f}/{no_yjit_cv:>4.1f}/{python_cv:>4.1f}%"
        )

    print()
    print("Per-component geometric means:")
    extensions = dict.fromkeys(row[0] for row in rows)
    for extension in extensions:
        extension_rows = [row for row in rows if row[0] == extension]
        yjit_gain = math.exp(
            statistics.fmean(math.log(row[5]) for row in extension_rows)
        )
        yjit_python = math.exp(
            statistics.fmean(math.log(row[6]) for row in extension_rows)
        )
        no_yjit_python = math.exp(
            statistics.fmean(math.log(row[7]) for row in extension_rows)
        )
        print(
            f"  {extension:<23} YJIT gain {yjit_gain:>6.2f}x  "
            f"YJIT/Python {yjit_python:>6.2f}x  NoYJIT/Python {no_yjit_python:>6.2f}x"
        )
    print()
    print("Correctness signatures matched for every compared workload.")


if __name__ == "__main__":
    main()
