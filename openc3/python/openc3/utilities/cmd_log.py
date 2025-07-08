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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.packet import Packet
from openc3.utilities.string import simple_formatted
from openc3.utilities.extract import convert_to_value


def _build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet):
    output_string = f'{method_name}("'
    output_string += target_name + " " + cmd_name
    if not cmd_params:
        output_string += '")'
    else:
        params = []
        for key, value in cmd_params.items():
            if key in Packet.RESERVED_ITEM_NAMES:
                continue

            found = False
            for item in packet["items"]:
                if item["name"] == key:
                    found = item
                    break
            if found and "data_type" in found:
                item_type = found["data_type"]
            else:
                item_type = None

            if found and found.get("obfuscate"):
                params.append(f"{key} *****")
            else:
                if isinstance(value, str):
                    if item_type == "BLOCK" or item_type == "STRING":
                        if not value.isascii():
                            value = "0x" + simple_formatted(value)
                        else:
                            value = f"'{str(value)}'"
                    else:
                        value = str(convert_to_value(value))
                    if len(value) > 256:
                        value = value[:256] + "...'"
                    value = value.replace('"', "'")
                elif isinstance(value, list):
                    value = f"[{', '.join(str(i) for i in value)}]"
                params.append(f"{key} {value}")
        output_string += " with " + ", ".join(params) + '")'
    return output_string