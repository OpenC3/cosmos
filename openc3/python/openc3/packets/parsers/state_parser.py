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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.packet_item import PacketItem
from openc3.utilities.logger import Logger
from openc3.utilities.extract import convert_to_value


class StateParser:
    COMMAND = "Command"
    TELEMETRY = "Telemetry"

    # self.param parser [ConfigParser] Configuration parser
    # self.param packet [Packet] The current packet
    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # self.param item [PacketItem] The packet item to create states on
    # self.param warnings [Array<String>] Array of string warnings which will be
    #   appended with any warnings found case parsing the limits:
    @classmethod
    def parse(cls, parser, packet, cmd_or_tlm, item, warnings):
        if item.limits.values:
            raise parser.error("Items with LIMITS can't define STATE")
        if item.units:
            raise parser.error("Items with UNITS can't define STATE")

        state_parser = StateParser(parser)
        state_parser.verify_parameters(cmd_or_tlm)
        state_parser.create_state(packet, cmd_or_tlm, item, warnings)

    # self.param parser [ConfigParser] Configuration parser
    def __init__(self, parser):
        self.parser = parser

    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    def verify_parameters(self, cmd_or_tlm):
        self.usage = "STATE <STATE NAME> <STATE VALUE> "
        if cmd_or_tlm == StateParser.COMMAND:
            self.usage += "<HAZARDOUS / DISABLE_MESSAGES (Optional)> <Hazardous Description (Optional)>"
            self.parser.verify_num_parameters(2, 4, self.usage)
        else:
            self.usage += "<COLOR: GREEN/YELLOW/RED (Optional)>"
            self.parser.verify_num_parameters(2, 3, self.usage)

    # self.param packet [Packet] The current packet
    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # self.param item [PacketItem] The packet item to create states on
    # self.param warnings [Array<String>] Array of string warnings which will be
    #   appended with any warnings found case parsing the limits:
    def create_state(self, packet, cmd_or_tlm, item, warnings):
        if item.states is None:
            item.states = {}

        state_name = self._get_state_name()
        self._check_for_duplicate_states(item, warnings)
        # Get the states, set one, then reassign for the setter to work
        states = item.states
        states[state_name] = self._get_state_value(item.data_type)
        item.states = states
        self._parse_additional_parameters(packet, cmd_or_tlm, item)

    def _get_state_name(self):
        return self.parser.parameters[0].upper()

    def _get_state_value(self, data_type):
        if data_type == "STRING" or data_type == "BLOCK":
            return self.parser.parameters[1]
        else:
            return convert_to_value(self.parser.parameters[1])

    def _check_for_duplicate_states(self, item, warnings):
        if item.states.get(self._get_state_name()) is not None:
            msg = f"Duplicate state defined on line {self.parser.line_number}: {self.parser.line}"
            Logger.warn(msg)
            warnings.append(msg)

    def _parse_additional_parameters(self, packet, cmd_or_tlm, item):
        if not len(self.parser.parameters) > 2:
            return

        if cmd_or_tlm == StateParser.COMMAND:
            self._get_hazardous_or_disable_messages(item)
        else:
            self._get_state_colors(item)
            packet.update_limits_items_cache(item)

    def _get_hazardous_or_disable_messages(self, item):
        match self.parser.parameters[2].upper():
            case "HAZARDOUS":
                if item.hazardous is None:
                    item.hazardous = {}
                if len(self.parser.parameters) >= 4:
                    item.hazardous[self._get_state_name()] = self.parser.parameters[3]
                else:
                    item.hazardous[self._get_state_name()] = ""
            case "DISABLE_MESSAGES":
                if item.messages_disabled is None:
                    item.messages_disabled = {}
                item.messages_disabled[self._get_state_name()] = True
            case _:
                raise self.parser.error(
                    "HAZARDOUS or DISABLE_MESSAGES expected as third parameter for this line.",
                    self.usage,
                )

    def _get_state_colors(self, item):
        color = self.parser.parameters[2].upper()
        if color not in PacketItem.STATE_COLORS:
            raise self.parser.error(
                f"Invalid state color {color}. Must be one of {' '.join(PacketItem.STATE_COLORS)}.",
                self.usage,
            )

        item.limits.enabled = True
        if item.state_colors is None:
            item.state_colors = {}
        item.state_colors[self._get_state_name()] = color
