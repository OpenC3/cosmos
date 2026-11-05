# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Times how long the Python PacketConfig takes to process the definition
# created by generate_cmd_tlm.rb, plus the as_json / json.dumps step
# TargetModel performs on every packet when it stores the target in Redis.
#
# Usage (from the openc3 directory):
#   uv run --project python python test/integration/cmd_tlm/benchmark_cmd_tlm.py [--no-descriptions] [generated_dir] [target]
#
# --no-descriptions drops descriptions while parsing, as the decom and interface
# microservices do. The JSON step then reflects that smaller definition.

import gc
import json
import os
import platform
import resource
import sys
import time


os.environ["OPENC3_NO_STORE"] = "1"

from openc3.packets.packet_config import PacketConfig  # noqa: E402
from openc3.utilities.logger import Logger  # noqa: E402


Logger.stdout = False


def rss_mb():
    # ru_maxrss is bytes on macOS and kilobytes on Linux. This is peak, not current.
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return rss / (1_048_576 if sys.platform == "darwin" else 1024)


def measure(label, func):
    gc.collect()
    start = time.monotonic()
    result = func()
    elapsed = time.monotonic() - start
    print(f"{label:<28} {elapsed:9.2f}s  peak RSS {rss_mb():8.1f} MB")
    return result, elapsed


def main():
    args = sys.argv[1:]
    descriptions = "--no-descriptions" not in args
    args = [arg for arg in args if arg != "--no-descriptions"]
    directory = args[0] if len(args) > 0 else os.path.join(os.path.dirname(__file__), "generated")
    target = (args[1] if len(args) > 1 else "BIG").upper()
    cmd_tlm_dir = os.path.join(directory, "targets", target, "cmd_tlm")
    tlm_file = os.path.join(cmd_tlm_dir, "tlm.txt")
    cmd_file = os.path.join(cmd_tlm_dir, "cmd.txt")
    for file in (tlm_file, cmd_file):
        if not os.path.exists(file):
            sys.exit(f"{file} not found. Run generate_cmd_tlm.rb first.")

    print(f"Python {platform.python_version()}{'' if descriptions else ' (no descriptions)'}")
    print(f"{'start':<28} {'':>10}  peak RSS {rss_mb():8.1f} MB")

    total = 0.0
    pc = PacketConfig(descriptions=descriptions)
    _, t = measure("process tlm.txt", lambda: pc.process_file(tlm_file, target))
    total += t
    _, t = measure("process cmd.txt", lambda: pc.process_file(cmd_file, target))
    total += t

    tlm = pc.telemetry[target]
    cmd = pc.commands[target]
    num_items = sum(len(p.sorted_items) for p in tlm.values())
    num_states = sum(len(i.states) if i.states else 0 for p in tlm.values() for i in p.sorted_items)
    num_params = sum(len(p.sorted_items) for p in cmd.values())

    def dump(packets):
        return sum(len(json.dumps(packet.as_json())) for packet in packets.values())

    tlm_bytes, t = measure("tlm as_json + json", lambda: dump(tlm))
    total += t
    cmd_bytes, t = measure("cmd as_json + json", lambda: dump(cmd))
    total += t

    print(f"{'total':<28} {total:9.2f}s")
    print(
        f"Parsed {len(tlm)} tlm packets, {num_items} items (incl. derived), {num_states} states; "
        f"{len(cmd)} cmd packets, {num_params} params (incl. derived)"
    )
    print(f"JSON size {(tlm_bytes + cmd_bytes) / 1_048_576:.1f} MB")


if __name__ == "__main__":
    main()
