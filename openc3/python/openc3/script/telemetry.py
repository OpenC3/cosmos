# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.script.api_shared import openc3_script_sleep


def get_packets(
    id: str, block: float | None = None, block_delay: float = 0.1, count: int = 1000, scope: str = OPENC3_SCOPE
):
    """Get packets based on ID returned from subscribe_packet.

    Args:
        id (str) ID returned from subscribe_packets or last call to get_packets
        block (float) Time in seconds to wait for packets to be received
        block_delay (float) Time in seconds to sleep between polls
        count (int) Maximum number of packets to return from EACH packet stream
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        [Array<String, Array<Hash>] Array of the ID and array of all packets found
    """
    start_time = time.time()
    while True:
        id, packets = openc3.script.API_SERVER.get_packets(id, count=count, scope=scope)
        if block and time.time() < (start_time + block) and not packets:
            openc3_script_sleep(block_delay)
        else:
            break
    return id, packets


# inject_tlm, set_tlm, override_tlm, and normalize_tlm are implemented here simply to add a print
# these methods modify the telemetry so the user should be notified in the Script Runner log messages


def inject_tlm(
    target_name: str, packet_name: str, item_hash: dict = None, type: str = "CONVERTED", scope: str = OPENC3_SCOPE
):
    print(f'inject_tlm("{target_name}", "{packet_name}", {item_hash}, type="{type}")')
    openc3.script.API_SERVER.inject_tlm(target_name, packet_name, item_hash, type=type, scope=scope)


def set_tlm(*args, type: str = "CONVERTED", scope: str = OPENC3_SCOPE):
    if len(args) == 1:
        print(f'set_tlm("{args[0]}", type="{type}")')
    else:
        if isinstance(args[3], str):
            value = f'"{args[3]}"'
        else:
            value = args[3]
        print(f'set_tlm("{args[0]}", "{args[1]}", "{args[2]}", {value}, type="{type}")')
    openc3.script.API_SERVER.set_tlm(*args, type=type, scope=scope)


def override_tlm(*args, type: str = "ALL", scope: str = OPENC3_SCOPE):
    if len(args) == 1:
        print(f'override_tlm("{args[0]}", type="{type}")')
    else:
        if isinstance(args[3], str):
            value = f'"{args[3]}"'
        else:
            value = args[3]
        print(f'override_tlm("{args[0]}", "{args[1]}", "{args[2]}", {value}, type="{type}")')
    openc3.script.API_SERVER.override_tlm(*args, type=type, scope=scope)


def normalize_tlm(*args, type: str = "ALL", scope: str = OPENC3_SCOPE):
    if len(args) == 1:
        print(f'normalize_tlm("{args[0]}", type="{type}")')
    else:
        if isinstance(args[3], str):
            value = f'"{args[3]}"'
        else:
            value = args[3]
        print(f'normalize_tlm("{args[0]}", "{args[1]}", "{args[2]}", {value}, type="{type}")')
    openc3.script.API_SERVER.normalize_tlm(*args, type=type, scope=scope)
